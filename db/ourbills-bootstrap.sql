-- ourbills: additive schema; Wealth PWA tables and policies are untouched.
create schema if not exists ourbills_private;
revoke all on schema ourbills_private from public, anon;
grant usage on schema ourbills_private to authenticated;

create table public.ourbills_books (
 id uuid primary key default gen_random_uuid(), name text not null check(char_length(name) between 1 and 100),
 owner_id uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table public.ourbills_members (
 book_id uuid not null references public.ourbills_books(id), user_id uuid not null references auth.users(id),
 display_name text not null check(char_length(display_name) between 1 and 50), joined_at timestamptz not null default now(),
 primary key(book_id,user_id)
);
create index ourbills_members_user_idx on public.ourbills_members(user_id,book_id);
create table public.ourbills_entries (
 id uuid primary key, book_id uuid not null references public.ourbills_books(id), place text not null check(char_length(place) between 1 and 120),
 amount_cents bigint not null check(amount_cents between 1 and 1000000000), payer_id uuid not null,
 shares jsonb not null check(jsonb_typeof(shares)='object'), expense_date date not null,
 note text not null default '' check(char_length(note)<=1000), receipt_path text,
 created_by uuid not null references auth.users(id), updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 version integer not null default 1, deleted_at timestamptz,
 foreign key(book_id,payer_id) references public.ourbills_members(book_id,user_id)
);
create index ourbills_entries_book_idx on public.ourbills_entries(book_id,expense_date desc);
create index ourbills_entries_created_idx on public.ourbills_entries(created_by);
create index ourbills_entries_updated_idx on public.ourbills_entries(updated_by);
create table public.ourbills_settlements (
 id uuid primary key, book_id uuid not null references public.ourbills_books(id), from_id uuid not null, to_id uuid not null,
 amount_cents bigint not null check(amount_cents between 1 and 1000000000), paid_date date not null,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(),
 check(from_id<>to_id), foreign key(book_id,from_id) references public.ourbills_members(book_id,user_id),
 foreign key(book_id,to_id) references public.ourbills_members(book_id,user_id)
);
create index ourbills_settlements_book_idx on public.ourbills_settlements(book_id,created_at desc);
create index ourbills_settlements_creator_idx on public.ourbills_settlements(created_by);
create table public.ourbills_audit (
 id bigint generated always as identity primary key, book_id uuid not null references public.ourbills_books(id),
 actor_id uuid not null references auth.users(id), action text not null, before_data jsonb, after_data jsonb,
 created_at timestamptz not null default now()
);
create index ourbills_audit_book_idx on public.ourbills_audit(book_id,id desc);
create index ourbills_audit_actor_idx on public.ourbills_audit(actor_id);
create index ourbills_books_owner_idx on public.ourbills_books(owner_id);
create table ourbills_private.invites (
 token_hash text primary key, book_id uuid not null references public.ourbills_books(id),
 created_by uuid not null references auth.users(id), expires_at timestamptz not null default now()+interval '7 days', used_by uuid, used_at timestamptz
);
alter table ourbills_private.invites enable row level security;

create function ourbills_private.is_member(b uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.ourbills_members m where m.book_id=b and m.user_id=(select auth.uid()));
$$;
revoke all on function ourbills_private.is_member(uuid) from public,anon;
grant execute on function ourbills_private.is_member(uuid) to authenticated;

alter table public.ourbills_books enable row level security;
alter table public.ourbills_members enable row level security;
alter table public.ourbills_entries enable row level security;
alter table public.ourbills_settlements enable row level security;
alter table public.ourbills_audit enable row level security;
create policy ourbills_books_read on public.ourbills_books for select to authenticated using(ourbills_private.is_member(id));
create policy ourbills_members_read on public.ourbills_members for select to authenticated using(ourbills_private.is_member(book_id));
create policy ourbills_entries_read on public.ourbills_entries for select to authenticated using(ourbills_private.is_member(book_id));
create policy ourbills_settlements_read on public.ourbills_settlements for select to authenticated using(ourbills_private.is_member(book_id));
create policy ourbills_audit_read on public.ourbills_audit for select to authenticated using(ourbills_private.is_member(book_id));
revoke all on public.ourbills_books,public.ourbills_members,public.ourbills_entries,public.ourbills_settlements,public.ourbills_audit from anon,authenticated;
grant select on public.ourbills_books,public.ourbills_members,public.ourbills_entries,public.ourbills_settlements,public.ourbills_audit to authenticated;

create function ourbills_private.action(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  insert into public.ourbills_books(name,owner_id) values(btrim(p->>'name'),u) returning * into book;
  b:=book.id;
  insert into public.ourbills_members(book_id,user_id,display_name) values(b,u,disp);
  insert into public.ourbills_audit(book_id,actor_id,action,after_data) values(b,u,op,to_jsonb(book));
  return to_jsonb(book);
 elsif op='join' then
  disp:=btrim(p->>'display_name');
  if disp is null or char_length(disp) not between 1 and 50 then raise exception 'Enter your display name'; end if;
  select * into inv from ourbills_private.invites where token_hash=encode(extensions.digest(p->>'token','sha256'),'hex') for update;
  if not found or inv.expires_at<now() or inv.used_by is not null then raise exception 'Invite expired or already used'; end if;
  b:=inv.book_id;
  perform 1 from public.ourbills_books where id=b for update;
  if exists(select 1 from public.ourbills_members where book_id=b and user_id=u) then return jsonb_build_object('id',b); end if;
  if (select count(*) from public.ourbills_members where book_id=b)>=20 then raise exception 'This book has reached 20 members'; end if;
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
revoke all on function ourbills_private.action(text,jsonb) from public,anon;
grant execute on function ourbills_private.action(text,jsonb) to authenticated;
create function public.ourbills_action(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$ select ourbills_private.action(op,p); $$;
revoke all on function public.ourbills_action(text,jsonb) from public,anon;
grant execute on function public.ourbills_action(text,jsonb) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('ourbills-receipts','ourbills-receipts',false,2097152,array['image/jpeg','image/png','image/webp']);
create policy ourbills_receipt_read on storage.objects for select to authenticated using(bucket_id='ourbills-receipts' and exists(select 1 from public.ourbills_members m where m.book_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid())));
create policy ourbills_receipt_upload on storage.objects for insert to authenticated with check(bucket_id='ourbills-receipts' and (storage.foldername(name))[2]=(select auth.uid())::text and exists(select 1 from public.ourbills_members m where m.book_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid())));
create policy ourbills_receipt_delete on storage.objects for delete to authenticated using(bucket_id='ourbills-receipts' and (storage.foldername(name))[2]=(select auth.uid())::text and exists(select 1 from public.ourbills_members m where m.book_id::text=(storage.foldername(name))[1] and m.user_id=(select auth.uid())));

create index ourbills_invites_book_idx on ourbills_private.invites(book_id); create index ourbills_invites_creator_idx on ourbills_private.invites(created_by); create index ourbills_entries_payer_idx on public.ourbills_entries(book_id,payer_id); create index ourbills_settlements_from_idx on public.ourbills_settlements(book_id,from_id); create index ourbills_settlements_to_idx on public.ourbills_settlements(book_id,to_id); create policy ourbills_invites_deny_direct on ourbills_private.invites for all to authenticated using(false) with check(false);
