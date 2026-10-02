# JalNigrani Supabase setup

Run `migrations/202609190001_create_jalnigrani_schema.sql` once in the Supabase SQL Editor. It contains no service-role key.

Set these browser-safe values in `.env.local`, then restart Vite:

```env
VITE_SUPABASE_READINGS_TABLE=water_readings
VITE_SUPABASE_ALERTS_TABLE=alerts
VITE_SUPABASE_DEVICES_TABLE=water_devices
VITE_SUPABASE_READINGS_TIME_COLUMN=recorded_at
```

Use only the project URL and publishable/anon key in `VITE_` variables. ESP32 telemetry must go through a server or Edge Function; retain its service-role key only in that server-side environment.

To make an administrator after that user has registered:

```sql
update public.profiles set role = 'admin' where id = '<auth-user-uuid>';
```
