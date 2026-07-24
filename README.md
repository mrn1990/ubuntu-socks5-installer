# Ubuntu SOCKS5 Installer

نصب تعاملی SOCKS5 روی Ubuntu با استفاده از Dante.

اسکریپت هنگام اجرا به‌ترتیب از شما می‌پرسد:

1. پورت به‌صورت تصادفی انتخاب شود یا دستی؟
2. نام کاربری SOCKS5 چه باشد؟
3. رمز عبور چه باشد؟
4. تأیید رمز عبور

در پایان، IP، پورت، نام کاربری، رمز عبور، لینک `socks5://`، لینک
`socks5h://` و دستور تست نمایش داده می‌شود.

## سیستم‌های پشتیبانی‌شده

- Ubuntu Server
- دسترسی `root` یا `sudo`
- معماری‌های معمول x86_64 و ARM64، مشروط به موجود بودن بسته
  `dante-server` در مخازن Ubuntu

## نصب یک‌خطی

ابتدا عبارت `YOUR_GITHUB_USERNAME` را با نام کاربری GitHub خود جایگزین کنید:

```bash
curl -fsSL https://raw.githubusercontent.com/mrn1990/ubuntu-socks5-installer/main/install.sh | sudo bash
```

اسکریپت ورودی‌های تعاملی را از `/dev/tty` می‌خواند؛ در نتیجه با وجود استفاده
از Pipe، سؤال‌های نصب در همان ترمینال نمایش داده می‌شوند.

## مراحل تعاملی

نمونه:

```text
Port selection:
  1) Choose a random free port
  2) Enter a port manually
Select [1/2]: 1

Enter SOCKS5 username: myproxy
Enter SOCKS5 password:
Confirm password:
```

برای رمز عبور محدودیت طول یا نوع کاراکتر اعمال نمی‌شود. کاراکترهای ویژه در
لینک‌های اتصال به‌صورت خودکار با percent-encoding نمایش داده می‌شوند.

## نمونه خروجی

```text
Server   : 203.0.113.10
Port     : 43821
Username : myproxy
Password : ExampleStrongPassword2026

SOCKS5 URL:
socks5://myproxy:ExampleStrongPassword2026@203.0.113.10:43821

SOCKS5 URL with remote DNS:
socks5h://myproxy:ExampleStrongPassword2026@203.0.113.10:43821
```

## تست اتصال

روی یک کامپیوتر دیگر اجرا کنید:

```bash
curl \
  --proxy 'socks5h://SERVER_IP:PORT' \
  --proxy-user 'USERNAME:PASSWORD' \
  https://api.ipify.org
```

اگر IP عمومی سرور نمایش داده شود، اتصال صحیح است.

## مشاهده مجدد اطلاعات اتصال

```bash
sudo cat /root/socks5-credentials.txt
```

فایل اطلاعات اتصال فقط برای کاربر root قابل خواندن است.

## مدیریت سرویس

وضعیت سرویس:

```bash
sudo systemctl status danted --no-pager
```

راه‌اندازی مجدد:

```bash
sudo systemctl restart danted
```

مشاهده لاگ‌ها:

```bash
sudo journalctl -u danted -n 100 --no-pager
```

بررسی پورت در حال Listen:

```bash
sudo ss -lntp | grep danted
```

## اجرای مجدد نصب

همان دستور نصب یک‌خطی را دوباره اجرا کنید. اسکریپت وجود نصب قبلی را تشخیص
می‌دهد و قبل از جایگزینی از شما تأیید می‌گیرد.

## فایروال

اگر UFW از قبل فعال باشد، اسکریپت پورت انتخاب‌شده را برای TCP باز می‌کند.

اگر ارائه‌دهنده VPS شما فایروال ابری جداگانه دارد، پورت نمایش‌داده‌شده را
در پنل ارائه‌دهنده نیز برای ورودی TCP باز کنید.

## ساخت ریپازیتوری GitHub

یک ریپازیتوری Public با نام زیر ایجاد کنید:

```text
ubuntu-socks5-installer
```

سپس فایل‌های این پروژه را داخل آن قرار دهید و اجرا کنید:

```bash
git init
git add install.sh README.md LICENSE
git commit -m "Add interactive Ubuntu SOCKS5 installer"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/ubuntu-socks5-installer.git
git push -u origin main
```

پس از Push، دستور نصب شما به شکل زیر خواهد بود:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/ubuntu-socks5-installer/main/install.sh | sudo bash
```

## نکات امنیتی

- نام کاربری و رمز عبور مانع Open Proxy شدن بدون احراز هویت می‌شوند.
- فقط اعضای گروه سیستمی `socks5users` اجازه استفاده از پراکسی را دارند.
- دسترسی از طریق پراکسی به آدرس‌های Loopback، شبکه‌های خصوصی و آدرس‌های
  Metadata مسدود شده است.
- احراز هویت Username/Password استاندارد SOCKS5 رمزنگاری سرتاسری ایجاد
  نمی‌کند. برای شبکه‌های غیرقابل‌اعتماد، استفاده از WireGuard یا تونل
  رمزنگاری‌شده امن‌تر است.
- برای استفاده عملیاتی حساس، دستور نصب را به یک Commit یا Release مشخص
  Pin کنید تا تغییرات آینده فایل `main` به‌طور ناخواسته اجرا نشوند.

## فایل‌های ایجادشده روی سرور

```text
/etc/danted.conf
/etc/socks5-installer.user
/root/socks5-credentials.txt
```

## مستندات مرجع

- Dante Server Documentation: https://www.inet.no/dante/doc/latest/config/server.html
- Dante Authentication Documentation: https://www.inet.no/dante/doc/latest/config/auth.html
- Dante Username Authentication: https://www.inet.no/dante/doc/latest/config/auth_username.html

## License

MIT
