# Persian Spoof Tunnel

<p align="center">
  <strong>مدیریت فارسی و ساده‌تر برای پروژه متن‌باز Spoof Tunnel</strong>
</p>

<p align="center">
  <a href="https://github.com/metallica1495/Persian-Spoof-Tunnel/actions"><img src="https://img.shields.io/github/actions/workflow/status/metallica1495/Persian-Spoof-Tunnel/check-shell.yml?branch=main&label=CI" alt="CI"></a>
  <a href="https://github.com/metallica1495/Persian-Spoof-Tunnel/commits/main"><img src="https://img.shields.io/github/last-commit/metallica1495/Persian-Spoof-Tunnel" alt="Last commit"></a>
  <a href="https://github.com/metallica1495/Persian-Spoof-Tunnel"><img src="https://img.shields.io/github/repo-size/metallica1495/Persian-Spoof-Tunnel" alt="Repository size"></a>
  <a href="https://github.com/ParsaKSH/spoof-tunnel"><img src="https://img.shields.io/badge/upstream-Spoof--Tunnel-blue" alt="Upstream"></a>
</p>

این مخزن یک لایه مدیریت و نصب فارسی برای هسته اصلی [Spoof Tunnel](https://github.com/ParsaKSH/spoof-tunnel) فراهم می‌کند. هدف، ساده‌تر کردن بررسی سیستم، مدیریت سرویس، نگهداری فایل‌های پیکربندی و دسترسی به پنل مدیریتی در سرورهای Linux است.

> **وضعیت پروژه:** کدها و آزمون‌های خودکار در GitHub قرار دارند. موفقیت CI فقط بررسی نحوی و آزمون‌های نرم‌افزاری را نشان می‌دهد؛ نصب و کارکرد روی سرور واقعی هنوز باید در محیط مجاز و کنترل‌شده آزمایش شود.

## فهرست

- [قابلیت‌ها](#قابلیت‌ها)
- [دریافت فایل‌ها](#دریافت-فایل‌ها)
- [ساختار پروژه](#ساختار-پروژه)
- [پنل وب فارسی](#پنل-وب-فارسی)
- [آزمون‌ها و وضعیت ساخت](#آزمون‌ها-وضعیت-ساخت)
- [پیش‌نیازها و سازگاری](#پیش‌نیازها-و-سازگاری)
- [مستندات و منابع](#مستندات-و-منابع)
- [امنیت و استفاده مسئولانه](#امنیت-و-استفاده-مسئولانه)
- [مجوز و پروژه بالادستی](#مجوز-و-پروژه-بالادستی)

## قابلیت‌ها

- منوی متنی فارسی برای مدیریت مراحل و مشاهده وضعیت.
- تشخیص سیستم‌عامل Linux و معماری‌های پشتیبانی‌شده در اسکریپت.
- بررسی و نصب پیش‌نیازهای عمومی موردنیاز اسکریپت.
- بررسی وضعیت سرویس‌های systemd و مشاهده گزارش‌ها.
- تهیه نسخه پشتیبان و اعتبارسنجی فایل‌های پیکربندی.
- گزارش خواندنی از رابط‌های شبکه، مسیر پیش‌فرض، IPهای پیکربندی‌شده و وضعیت ابزارهای فایروال.
- پنل وب فارسی با ورود مدیر، نشست امن، محافظت CSRF و داشبورد منابع سیستم.
- اجرای پنل مدیریتی روی localhost و امکان دسترسی امن از طریق تونل SSH.
- آزمون‌های خودکار Python و بررسی نحوی Bash در GitHub Actions.

این مخزن هسته اصلی را بازنویسی نمی‌کند؛ نسخه هسته مورد استفاده در اسکریپت در فایل راهنمای فارسی مشخص شده است.

## دریافت فایل‌ها

فایل‌های اصلی پروژه را از این مسیرها ببینید:

| بخش | پیوند |
|---|---|
| اسکریپت نصب و منوی مدیریت | [install.sh](https://github.com/metallica1495/Persian-Spoof-Tunnel/blob/main/install.sh) |
| راهنمای کامل فارسی | [README-fa.md](https://github.com/metallica1495/Persian-Spoof-Tunnel/blob/main/README-fa.md) |
| کد پنل وب فارسی | [پوشه panel](https://github.com/metallica1495/Persian-Spoof-Tunnel/tree/main/panel) |
| آزمون‌های پنل | [test_app.py](https://github.com/metallica1495/Persian-Spoof-Tunnel/blob/main/panel/test_app.py) |
| گردش‌کار بررسی خودکار | [GitHub Actions](https://github.com/metallica1495/Persian-Spoof-Tunnel/tree/main/.github/workflows) |
| تاریخچه تغییرات | [Commits](https://github.com/metallica1495/Persian-Spoof-Tunnel/commits/main) |

برای مشاهده جزئیات نصب، تنظیمات و مسیرهای فایل‌ها، راهنمای کامل فارسی را مطالعه کنید. فایل اسکریپت را پیش از هر اجرا بررسی کنید و فقط در سرورهایی که مالک آن هستید یا مجوز مدیریتشان را دارید به کار ببرید.

## ساختار پروژه

```text
.
├── install.sh
├── README.md
├── README-fa.md
├── panel/
│   ├── app.py
│   └── test_app.py
└── .github/
    └── workflows/
        └── check-shell.yml
```

## پنل وب فارسی

پنل وب برای نمایش وضعیت سرور و سرویس، منابع سیستم و گزارش‌های سرویس طراحی شده است. احراز هویت مدیر، نشست امن و محافظت CSRF در آن پیاده‌سازی شده است. پنل به‌صورت پیش‌فرض روی `127.0.0.1:8787` گوش می‌دهد؛ آن را بدون لایه امنیتی مناسب مستقیماً در اینترنت منتشر نکنید.

راهنمای نصب پنل، ورود و دسترسی از راه دور در [README-fa.md](https://github.com/metallica1495/Persian-Spoof-Tunnel/blob/main/README-fa.md) آمده است.

## آزمون‌ها و وضعیت ساخت

GitHub Actions موارد زیر را بررسی می‌کند:

- صحت نحوی اسکریپت Bash.
- کامپایل فایل‌های Python.
- اجرای آزمون‌های واحد پنل.

[مشاهده آخرین اجراهای CI](https://github.com/metallica1495/Persian-Spoof-Tunnel/actions)

سبز بودن CI به‌تنهایی به معنی آزمایش نصب روی همه توزیع‌ها، ارائه‌دهندگان VPS یا توپولوژی‌های شبکه نیست.

## پیش‌نیازها و سازگاری

- سیستم‌عامل Linux دارای systemd.
- دسترسی مدیریتی متناسب با عملیات سیستم.
- ابزارهای عمومی مانند Python 3 و curl؛ اسکریپت برای نصب برخی پیش‌نیازهای عمومی از package managerهای رایج پشتیبانی می‌کند.
- جزئیات شبکه باید توسط مدیر مجاز همان سرور تأیید شوند.

## مستندات و منابع

- [راهنمای کامل فارسی همین پروژه](README-fa.md)
- [مخزن اصلی Spoof Tunnel](https://github.com/ParsaKSH/spoof-tunnel)
- [راهنمای فارسی پروژه اصلی](https://github.com/ParsaKSH/spoof-tunnel/blob/main/README-fa.md)
- [نسخه هسته مورد اشاره در راهنما](https://github.com/ParsaKSH/spoof-tunnel/releases/tag/v3.1.0-beta.0)

## امنیت و استفاده مسئولانه

- فقط روی زیرساختی استفاده کنید که مالک آن هستید یا مجوز صریح مدیریت آن را دارید.
- پیش از اجرای هر اسکریپت با دسترسی root، محتوای آن را بازبینی کنید.
- رمزها، فایل‌های پیکربندی خصوصی، IPهای حساس و نسخه‌های پشتیبان را در مخزن Git قرار ندهید.
- قوانین فایروال و دسترسی SSH را پیش از هر تغییر بررسی کنید تا دسترسی مدیریتی قطع نشود.
- گزارش IP عمومی یا رابط شبکه به‌تنهایی مجوز استفاده از آن آدرس یا دسترسی به شبکه دیگران را اثبات نمی‌کند.

## مجوز و پروژه بالادستی

این مخزن یک ابزار مدیریتی پیرامون پروژه بالادستی است. پیش از بازنشر یا توزیع نسخه‌های ترکیبی، مجوز و شرایط هر دو پروژه و وابستگی‌ها را بررسی کنید. کد اصلی و تاریخچه آن در [مخزن ParsaKSH/spoof-tunnel](https://github.com/ParsaKSH/spoof-tunnel) نگهداری می‌شود.
