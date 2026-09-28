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
