begin;
do $$
declare
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 book uuid; other uuid; couple uuid; token text; oldtoken text; e1 uuid:=gen_random_uuid(); e2 uuid:=gen_random_uuid(); r jsonb;
begin
 insert into auth.users(id,email) values(a,'ourbills-test-a-'||a||'@example.invalid'),(b,'ourbills-test-b-'||b||'@example.invalid'),(c,'ourbills-test-c-'||c||'@example.invalid');
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 r:=public.ourbills_action('create_book',jsonb_build_object('name','test book A','display_name','Alice')); book:=(r->>'id')::uuid;
 r:=public.ourbills_action('invite',jsonb_build_object('book_id',book));token:=r->>'token';
 perform set_config('request.jwt.claim.sub',b::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
 if exists(select 1 from public.ourbills_books where id=book) then raise exception 'FAIL: outsider can read'; end if;
 begin
  perform public.ourbills_action('invite',jsonb_build_object('book_id',book));
  raise exception 'FAIL: outsider can write';
 exception when insufficient_privilege then null; end;
 perform public.ourbills_action('join',jsonb_build_object('token',token,'display_name','Bob'));
 if not exists(select 1 from public.ourbills_books where id=book) then raise exception 'FAIL: member cannot read'; end if;
 begin
  perform public.ourbills_action('invite',jsonb_build_object('book_id',book));raise exception 'FAIL: member can invite';
 exception when insufficient_privilege then null;end;
 r:=public.ourbills_action('create_book',jsonb_build_object('name','test book B','display_name','Bob'));other:=(r->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 if exists(select 1 from public.ourbills_books where id=other) then raise exception 'FAIL: cross book access';end if;
 if exists(select 1 from public.user_wealth_data) then raise exception 'FAIL: Wealth data exposed';end if;
 r:=public.ourbills_action('add_entry',jsonb_build_object('id',e1,'book_id',book,'place','Dinner','amount_cents',80000,'payer_id',a,'shares',jsonb_build_object(a::text,40000,b::text,40000),'expense_date',current_date));
 perform public.ourbills_action('add_entry',jsonb_build_object('id',e1,'book_id',book));
 if (select count(*) from public.ourbills_entries where book_id=book)<>1 then raise exception 'FAIL: duplicate save';end if;
 r:=public.ourbills_action('add_entry',jsonb_build_object('id',e2,'book_id',book,'place','Coffee','amount_cents',20000,'payer_id',b,'shares',jsonb_build_object(a::text,10000,b::text,10000),'expense_date',current_date));
 begin
  perform public.ourbills_action('settle',jsonb_build_object('id',gen_random_uuid(),'book_id',book,'from_id',b,'to_id',a,'amount_cents',30001,'paid_date',current_date));
  raise exception 'FAIL: overpayment accepted';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 r:=public.ourbills_action('settle',jsonb_build_object('id',gen_random_uuid(),'book_id',book,'from_id',b,'to_id',a,'amount_cents',30000,'paid_date',current_date));
 begin
  perform public.ourbills_action('settle',jsonb_build_object('id',gen_random_uuid(),'book_id',book,'from_id',b,'to_id',a,'amount_cents',1,'paid_date',current_date));raise exception 'FAIL: settled twice';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin
  perform public.ourbills_action('edit_entry',jsonb_build_object('id',e1,'book_id',book,'version',2));raise exception 'FAIL: stale edit';
 exception when serialization_failure then null;end;
 begin
  perform public.ourbills_action('add_entry',jsonb_build_object('id',gen_random_uuid(),'book_id',book,'place','Bad split','amount_cents',100,'payer_id',a,'shares',jsonb_build_object(c::text,100),'expense_date',current_date));raise exception 'FAIL: outsider split';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin
  insert into public.ourbills_books(name,owner_id) values('bypass',a);raise exception 'FAIL: direct write';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',c::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated')::text,true);
 begin
  perform public.ourbills_action('join',jsonb_build_object('token',token,'display_name','Charlie'));raise exception 'FAIL: reused invite';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 if exists(select 1 from public.ourbills_entries) then raise exception 'FAIL: entries leaked';end if;
 if exists(select 1 from public.ourbills_audit) then raise exception 'FAIL: audit leaked';end if;

 -- Couple capacity is enforced in SQL, including multiple issued invite tokens.
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 r:=public.ourbills_action('create_book',jsonb_build_object('name','test couple','display_name','Alice','mode','couple'));couple:=(r->>'id')::uuid;
 if (select mode from public.ourbills_books where id=couple)<>'couple' then raise exception 'FAIL: couple mode';end if;
 r:=public.ourbills_action('invite',jsonb_build_object('book_id',couple));oldtoken:=r->>'token';
 r:=public.ourbills_action('invite',jsonb_build_object('book_id',couple));token:=r->>'token';
 perform set_config('request.jwt.claim.sub',b::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
 begin
  perform public.ourbills_action('join',jsonb_build_object('token',oldtoken,'display_name','Bob'));raise exception 'FAIL: rotated token accepted';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 perform public.ourbills_action('join',jsonb_build_object('token',token,'display_name','Bob'));
 if (select count(*) from public.ourbills_members where book_id=couple)<>2 then raise exception 'FAIL: missing partner';end if;
 if (select display_name from public.ourbills_members where book_id=couple and user_id=b)<>'Bob' then raise exception 'FAIL: lost account identity';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 begin
  perform public.ourbills_action('invite',jsonb_build_object('book_id',couple));raise exception 'FAIL: full couple can invite';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 -- Direct changes cannot turn a couple into a group or impersonate a member.
 begin
  update public.ourbills_books set mode='shared' where id=couple;raise exception 'FAIL: direct mode write';
 exception when insufficient_privilege then null;end;
 execute 'reset role';
 -- Simulate a second already-issued valid token to exercise capacity independently of token reuse.
 oldtoken:=gen_random_uuid()::text;
 insert into ourbills_private.invites(token_hash,book_id,created_by) values(encode(extensions.digest(oldtoken,'sha256'),'hex'),couple,a);
 perform set_config('request.jwt.claim.sub',c::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 begin
  perform public.ourbills_action('join',jsonb_build_object('token',oldtoken,'display_name','Charlie'));raise exception 'FAIL: third member admitted';
 exception when raise_exception then if sqlerrm like 'FAIL:%' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claims','{}',true);
 begin
  perform public.ourbills_action('create_book',jsonb_build_object('name','anonymous','display_name','Unknown'));raise exception 'FAIL: missing auth accepted';
 exception when insufficient_privilege then null;end;
 execute 'reset role';
 execute 'set local role anon';
 begin
  perform public.ourbills_action('invite',jsonb_build_object('book_id',couple));raise exception 'FAIL: anon RPC';
 exception when insufficient_privilege then null;end;
 execute 'reset role';
end $$;
rollback;
select 'PASS: isolated books, invite-only membership, single-use invite, owner-only invitations, Wealth isolation, direct-write denial, idempotency, exact settlement, overpayment guard, stale-edit conflict, split validation, audit isolation. Couple capacity, rotated tokens, persisted member identity, anonymous denial. Test records rolled back.' as result;
