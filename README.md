# riset-flutter-receive-sms

Gateway SMS → HTTP buat riset IoT.

```
[SIM9600 / alat IoT] --SMS--> [SIM di HP] --> [App ini] --> [Backend]
                          (receive_sms)   (SQLite)      (belum ada)
```

Alat IoT (modul GSM SIM9600) kirim data sensor sebagai SMS ke nomor SIM di HP ini.
App menangkap SMS-nya, menyimpan ke SQLite, dan (nanti) meneruskan ke backend.

## Cara kerja capture SMS

| Kondisi HP/App | Mekanisme |
|---|---|
| App terbuka | stream `receive_sms` → instan ke UI + DB |
| App di-swipe / di-kill / OOM | SMS tetap masuk inbox sistem → disinkron saat app dibuka |
| Force stop | sama — disinkron saat app dibuka |
| HP mati | SMS ditahan operator → masuk inbox sistem saat nyala → disinkron saat app dibuka |

Izin (`READ_SMS` + `RECEIVE_SMS`) diminta sekali; setelah granted, app selanjutnya
langsung cek status senyap tanpa dialog.

## Filter nomor pengirim

Buka menu **filter** (ikon di AppBar kanan) untuk atur nomor yang boleh diproses
(misal nomor SIM di modem GSM SIM9600):

- Cuma SMS dari nomor terdaftar yang disimpan → otomatis juga yang diteruskan
  ke backend nanti
- Daftar **kosong = semua nomor dibaca** (perilaku default buat testing)
- Nomor dinormalisasi dulu: `0812…` = `+62812…` = `62812…` = `812…`
- Match **exact** setelah normalisasi — nomor lain yang mirip tidak ikut kebaca

## Terus ke backend

Isi **URL backend** di halaman Pengaturan (ikon filter) → `http://<ip-laptop>:5000`
(jalankan backend: `uv run app.py` di repo `riset-backend-receive-sms`).

- Tiap SMS baru (lolos filter nomor) di-POST ke `POST /api/sms`
- **Antrian lokal**: kolom `forwarded` — kalau backend lagi mati, SMS nunggu di
  DB dan dikirim ulang otomatis saat ada pemicu berikutnya (SMS masuk / app
  dibuka lagi). Status card nunjukkin jumlah yang menunggu
- Tombol **Tes koneksi** di Pengaturan mengecek `GET /api/health`
- Backend menyimpan ke `sms_log.txt` (JSON Lines) — sementara, bisa diganti DB

Catatan jaringan:

- Backend listen `0.0.0.0` supaya bisa diakses dari Wi-Fi yang sama — itu alamat
  **listen**, bukan tujuan. Di app **jangan** isi `0.0.0.0` (HP akan nembak ke
  HP-nya sendiri), isi IP laptop. Guard otomatis nolak input `0.0.0.0`
- CORS tidak berpengaruh buat Flutter mobile (cuma browser yang enforce)
- Kalau backend di Wi-Fi publik, set env `SMS_API_KEY` lalu isi `X-Api-Key` —
  sekarang app belum ngirim header itu, jadi pakai LAN pribadi dulu

## Menyimpan

- DB: `sms.db`, tabel `sms_entries`
- Dedupe otomatis: `UNIQUE(address, body, timestamp)` + `INSERT OR IGNORE`,
  jadi stream live dan sync inbox tidak pernah menggandakan data
- Sinkron inbox inkremental: hanya `date > max(timestamp)` yang sudah ada di DB
  (pertama kali: import seluruh inbox sekali)
- Hapus per item: swipe kiri (ada Urungkan); tombol sapu = hapus semua

## Limitasi (kebijakan Android, bukan bug)

- Saat app tertutup tidak ada UI yang jalan → data muncul **begitu app dibuka**,
  bukan push real-time. Itu batas maksimum Android.
- **Force stop** (Settings → Force stop) membuat app tidak menerima broadcast
  apa pun sampai dibuka manual. Tertangani oleh sync-on-open.
- `READ_SMS` adalah izin sensitif. Aman untuk riset/sideload; kalau mau naik ke
  Play Store, Google Play punya kebijakan khusus untuk izin SMS.

## Jalanin

```bash
flutter pub get
flutter analyze
flutter test
flutter run   # device Android, kirim SMS ke nomor SIM di HP
```
