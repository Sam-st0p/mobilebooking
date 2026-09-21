# How to run

Start **Laravel first**, then Flutter. Use two separate terminals and keep both open.

## 1. Laravel (backend)

```powershell
cd mobilebooking-backend
php artisan optimize:clear
php artisan serve
```

Runs at `http://127.0.0.1:8000`.

First time only (before the steps above):

```powershell
composer install
php artisan key:generate
```

Also make sure `.env` exists and is filled in (database and Supabase keys).

## 2. Flutter (app)

```powershell
cd mobilebooking
flutter pub get
flutter run -d chrome --web-port 5000
```

- `r` = hot reload, `R` = hot restart, `q` = quit.
- Use `--web-port 5000` so Chrome keeps you signed in.
- Android emulator: add `--dart-define=API_BASE_URL=http://10.0.2.2:8000/api`

## Tips

- Changed a Laravel file or `.env`? Run `php artisan optimize:clear`, then stop and start `php artisan serve` again.
- Something failing? Look at the last lines of `mobilebooking-backend\storage\logs\laravel.log`.