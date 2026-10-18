-- Profile photos: private bucket, one folder per user (<user id>/<n>.jpg).
-- Signed-in people can view photos (the feed shows them); only the owner can change their folder.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

create policy "signed-in people can view profile photos"
  on storage.objects for select to authenticated
  using (bucket_id = 'profile-photos');

create policy "owners upload their photos"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "owners update their photos"
  on storage.objects for update to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "owners delete their photos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = auth.uid()::text);
