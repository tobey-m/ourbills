-- Additive 3.0 upgrade. Existing spaces remain shared, with every row retained.
alter table public.ourbills_books add column mode text not null default 'shared' check(mode in ('shared','couple'));
create or replace function ourbills_private.action(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid(); b uuid; rid uuid; tok uuid; old public.ourbills_entries; fresh public.ourbills_entries;
 k text; v jsonb; sum_cents bigint:=0; amt bigint; payer uuid; f uuid; t uuid; debt bigint; credit bigint;
 book public.ourbills_books; inv ourbills_private.invites; result jsonb; disp text;
begin
 if u is null then raise exception 'Sign in required' using errcode='42501'; end if;
 if octet_length(p::text)>20000 then raise exception 'Request too large'; end if;
 if op='create_book' then
  disp:=btrim(p->>'display_name');
  if disp is null or char_length(disp) not between 1 and 50 then raise exception 'Enter your display name'; end if;
  insert into public.ourbills_books(name,owner_id,mode) values(btrim(p->>'name'),u,case when p->>'mode'='couple' then 'couple' else 'shared' end) returning * into book;
  b:=book.id;
  insert into public.ourbills_members(book_id,user_id,display_name) values(b,u,disp);
  insert into public.ourbills_audit(book_id,actor_id,action,after_data) values(b,u,op,to_jsonb(book));
  return to_jsonb(book);
 elsif op='join' then
  disp:=btrim(p->>'display_name');
  if disp is null or char_length(disp) not between 1 and 50 then raise exception 'Enter your display name'; end if;
  select * into inv from ourbills_private.invites where token_hash=encode(extensions.digest(p->>'token','sha256'),'hex');
  if not found then raise exception 'Invite expired or already used'; end if;
  b:=inv.book_id;
  -- All invite mutations lock the book before the token, including rotation.
  select * into book from public.ourbills_books where id=b for update;
  select * into inv from ourbills_private.invites where token_hash=encode(extensions.digest(p->>'token','sha256'),'hex') for update;
  if not found or inv.expires_at<=now() or inv.used_by is not null then raise exception 'Invite expired or already used'; end if;
  if exists(select 1 from public.ourbills_members where book_id=b and user_id=u) then return jsonb_build_object('id',b); end if;
  if (select count(*) from public.ourbills_members where book_id=b)>=(case when book.mode='couple' then 2 else 20 end) then raise exception 'พื้นที่นี้มีสมาชิกครบแล้ว'; end if;
  insert into public.ourbills_members(book_id,user_id,display_name) values(b,u,disp);
  update ourbills_private.invites set used_by=u,used_at=now() where token_hash=inv.token_hash;
  insert into public.ourbills_audit(book_id,actor_id,action,after_data) values(b,u,op,jsonb_build_object('display_name',disp));
  return jsonb_build_object('id',b);
 end if;
 b:=(p->>'book_id')::uuid;
 select * into book from public.ourbills_books where id=b for update;
 if not found or not ourbills_private.is_member(b) then raise exception 'Book access denied' using errcode='42501'; end if;
 if op='invite' then
  if book.owner_id<>u then raise exception 'Only the owner can invite' using errcode='42501'; end if;
  if book.mode='couple' then
   if (select count(*) from public.ourbills_members where book_id=b)>=2 then raise exception 'พื้นที่คู่รักมีสมาชิกครบสองคนแล้ว'; end if;
   update ourbills_private.invites set expires_at=now() where book_id=b and used_by is null;
  end if;
  tok:=gen_random_uuid();
  insert into ourbills_private.invites(token_hash,book_id,created_by) values(encode(extensions.digest(tok::text,'sha256'),'hex'),b,u);
  return jsonb_build_object('token',tok,'expires_at',now()+interval '7 days');
 elsif op='revoke_invites' then
  if book.owner_id<>u then raise exception 'Only the owner can revoke invites' using errcode='42501'; end if;
  update ourbills_private.invites set expires_at=now() where book_id=b and used_by is null;
  result:='{}'::jsonb;
 elsif op in ('add_entry','edit_entry','delete_entry') then
  rid:=(p->>'id')::uuid;
  select * into old from public.ourbills_entries where id=rid;
  if op='add_entry' and found then
   if old.book_id=b and old.created_by=u then return to_jsonb(old); end if;
   raise exception 'Entry id already used';
  end if;
  if op<>'add_entry' then
   if old.id is null or old.book_id<>b or old.deleted_at is not null then raise exception 'Entry not found'; end if;
   if old.version<>(p->>'version')::integer or p->>'version' is null then raise exception 'This bill changed. Refresh and review before saving.' using errcode='40001'; end if;
  end if;
  if op='delete_entry' then
   update public.ourbills_entries set deleted_at=now(),version=version+1,updated_by=u,updated_at=now() where id=rid returning * into fresh;
  else
   amt:=(p->>'amount_cents')::bigint; payer:=(p->>'payer_id')::uuid;
   if jsonb_typeof(p->'shares') is distinct from 'object' or (select count(*) from jsonb_object_keys(p->'shares'))=0 then raise exception 'Choose who shares this expense'; end if;
   for k,v in select * from jsonb_each(p->'shares') loop
    if jsonb_typeof(v)<>'number' or v::text !~ '^[0-9]+$' or v::text::numeric>1000000000 then raise exception 'Invalid split amount'; end if;
    if not exists(select 1 from public.ourbills_members where book_id=b and user_id=k::uuid) then raise exception 'Split member is not in this book'; end if;
    sum_cents:=sum_cents+v::text::bigint;
   end loop;
   if sum_cents<>amt then raise exception 'Split must equal the expense total'; end if;
   if p->>'receipt_path' is not null and ((p->>'receipt_path') not like b::text||'/%' or not exists(select 1 from storage.objects where bucket_id='ourbills-receipts' and name=p->>'receipt_path')) then raise exception 'Invalid receipt'; end if;
   if op='add_entry' then
    insert into public.ourbills_entries(id,book_id,place,amount_cents,payer_id,shares,expense_date,note,receipt_path,created_by,updated_by)
     values(rid,b,btrim(p->>'place'),amt,payer,p->'shares',(p->>'expense_date')::date,coalesce(p->>'note',''),p->>'receipt_path',u,u) returning * into fresh;
   else
    update public.ourbills_entries set place=btrim(p->>'place'),amount_cents=amt,payer_id=payer,shares=p->'shares',expense_date=(p->>'expense_date')::date,note=coalesce(p->>'note',''),receipt_path=p->>'receipt_path',updated_by=u,updated_at=now(),version=version+1 where id=rid returning * into fresh;
   end if;
  end if;
  insert into public.ourbills_audit(book_id,actor_id,action,before_data,after_data) values(b,u,op,case when op='add_entry' then null else to_jsonb(old) end,to_jsonb(fresh));
  return to_jsonb(fresh);
 elsif op='settle' then
  rid:=(p->>'id')::uuid; f:=(p->>'from_id')::uuid; t:=(p->>'to_id')::uuid; amt:=(p->>'amount_cents')::bigint;
  select to_jsonb(s) into result from public.ourbills_settlements s where id=rid and book_id=b and created_by=u;
  if found then return result; end if;
  select coalesce(sum((case when payer_id=f then amount_cents else 0 end)-coalesce((shares->>f::text)::bigint,0)),0) into debt from public.ourbills_entries where book_id=b and deleted_at is null;
  select debt+coalesce(sum(case when from_id=f then amount_cents when to_id=f then -amount_cents else 0 end),0) into debt from public.ourbills_settlements where book_id=b;
  select coalesce(sum((case when payer_id=t then amount_cents else 0 end)-coalesce((shares->>t::text)::bigint,0)),0) into credit from public.ourbills_entries where book_id=b and deleted_at is null;
  select credit+coalesce(sum(case when from_id=t then amount_cents when to_id=t then -amount_cents else 0 end),0) into credit from public.ourbills_settlements where book_id=b;
  if amt<=0 or amt>least(-debt,credit) then raise exception 'Settlement exceeds the current outstanding balance. Refresh first.'; end if;
  insert into public.ourbills_settlements(id,book_id,from_id,to_id,amount_cents,paid_date,created_by) values(rid,b,f,t,amt,(p->>'paid_date')::date,u) returning to_jsonb(ourbills_settlements.*) into result;
 else raise exception 'Unknown action';
 end if;
 insert into public.ourbills_audit(book_id,actor_id,action,after_data) values(b,u,op,result);
 return result;
end;
$$;
