# 🦈 BIGSHARK WEAPON CODES

Website lưu trữ và chia sẻ **code cấu hình súng** cho game **Delta Force**.

- Khách xem, tìm kiếm, sao chép code — không cần đăng ký
- Chỉ admin được thêm/sửa/xóa dữ liệu
- Bảo mật bằng Supabase Auth + Row Level Security (RLS)

---

## 🛠 Công nghệ

| Lớp | Công nghệ |
|-----|-----------|
| Frontend | HTML5 + CSS3 + Vanilla JS (ES Modules) |
| Build tool | Vite 5 |
| Backend / DB | Supabase (PostgreSQL + Auth + RLS) |
| Hosting | Vercel |

---

## 🚀 Hướng dẫn triển khai

### Bước 1 — Tạo Supabase project

1. Đăng ký tại [supabase.com](https://supabase.com) → tạo project mới
2. Vào **Project Settings → API**, lưu lại:
   - **Project URL** (dạng `https://xxxx.supabase.co`)
   - **anon public key** *(dùng cho frontend — an toàn để public)*

> ⚠️ **KHÔNG** dùng `service_role` key trong frontend bao giờ.

---

### Bước 2 — Chạy SQL Migration

1. Vào Supabase Dashboard → **SQL Editor**
2. Bật extension `pg_trgm` trước *(nếu chưa bật)*:
   - Vào **Database → Extensions** → tìm `pg_trgm` → bật ON
3. Copy toàn bộ nội dung file [`supabase/migrations/001_initial_schema.sql`](./supabase/migrations/001_initial_schema.sql)
4. Paste vào SQL Editor → nhấn **Run**
5. Chạy file `supabase/migrations/002_community_submissions.sql` (nếu chưa chạy).
6. Chạy file `supabase/migrations/003_moderation_hardening.sql` để tối ưu lọc trạng thái đóng góp và chống trùng lặp khi duyệt.
7. Chạy file `supabase/migrations/004_owner_moderator_roles.sql` để kích hoạt phân quyền 2 cấp `OWNER` và `MODERATOR`.

Migration 001 tạo:
- Bảng `weapon_codes` (id, weapon_name, weapon_code, timestamps)
- Bảng `admin_roles` (xác định ai là admin)
- Function `is_admin()` để check quyền phía server
- Trigger tự cập nhật `updated_at`
- Toàn bộ RLS policies

Migration 002 bổ sung:
- Metadata `game_mode` và `platform` cho code súng
- Bảng `weapon_submissions` cho đóng góp công khai, mặc định chờ duyệt
- RLS: khách chỉ được gửi đóng góp; chỉ admin đọc danh sách chờ duyệt
- RPC `review_weapon_submission` để duyệt/từ chối an toàn và duyệt + thêm vào kho trong một transaction

---

### Bước 3 — Tạo tài khoản Owner & Moderator

**Chỉ tạo tài khoản qua Supabase Dashboard — KHÔNG tạo form đăng ký công khai.**

1. Vào **Authentication → Users → Add user**
2. Nhập email + mật khẩu → tick **"Auto Confirm User"** → **Create User**
3. Copy **User UID** (UUID) của user vừa tạo
4. Vào **SQL Editor**, chạy:

```sql
-- Cấp quyền OWNER (Quản trị viên chính - toàn quyền, bao gồm xóa súng & phân quyền)
INSERT INTO public.admin_roles (user_id, role, granted_by)
VALUES ('PASTE_OWNER_UUID_HERE', 'OWNER', 'owner');

-- Cấp quyền MODERATOR (Quản trị viên phụ - thêm/sửa súng & duyệt đóng góp, KHÔNG được xóa)
INSERT INTO public.admin_roles (user_id, role, granted_by)
VALUES ('PASTE_MOD_UUID_HERE', 'MODERATOR', 'owner');
```

> Sau khi có tài khoản **OWNER**, bạn cũng có thể đăng nhập `/admin/login.html` và cấp/thu hồi quyền **MODERATOR** trực tiếp trong mục **Quản lý tài khoản & phân quyền**.

---

### Bước 4 — Cấu hình môi trường local

```bash
# Copy file env mẫu
cp .env.example .env
```

Mở `.env` và điền:

```env
VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key-here

# Optional: link donate và URL ảnh QR do nền tảng donate cung cấp
VITE_DONATE_URL=
VITE_DONATE_QR_URL=
```

---

### Bước 5 — Chạy local

```bash
npm install
npm run dev
```

Truy cập:
- Trang chủ: http://localhost:5173
- Trang admin: http://localhost:5173/admin/login.html

---

### Bước 6 — Deploy lên Vercel

1. Push code lên GitHub (đảm bảo `.env` đã có trong `.gitignore`)
2. Vào [vercel.com](https://vercel.com) → **Add New Project** → Import từ GitHub
3. Vào **Settings → Environment Variables**, thêm:

   | Key | Value |
   |-----|-------|
   | `VITE_SUPABASE_URL` | URL project Supabase |
   | `VITE_SUPABASE_ANON_KEY` | Anon key Supabase |
   | `VITE_DONATE_URL` | (Tùy chọn) Link trang donate |
   | `VITE_DONATE_QR_URL` | (Tùy chọn) URL ảnh QR donate |

4. **Deploy** — Vercel tự động chạy `npm run build`

> **Lưu ý:** Biến `VITE_*` được nhúng vào bundle lúc build. Đây là anon key — an toàn để public vì RLS bảo vệ dữ liệu ở tầng database.

---

## 🔐 Bảo mật & Phân quyền

### Mô hình phân quyền

```
Khách (anon)              → SELECT weapon_codes (chỉ đọc)
Đã đăng nhập, không admin → SELECT weapon_codes (chỉ đọc)
Admin (có trong admin_roles) → SELECT + INSERT + UPDATE + DELETE
```

### Cơ chế hoạt động

- **RLS bật** trên cả hai bảng
- Quyền admin được xác minh **phía database** qua bảng `admin_roles` — không thể giả mạo từ client
- Người dùng **không thể tự thêm mình** vào `admin_roles` (không có INSERT policy từ client)
- Chỉ `service_role` (Supabase Dashboard/SQL Editor) mới ghi được vào `admin_roles`
- Frontend chỉ chứa **anon key** — không có secret nào

### Những điều tuyệt đối KHÔNG làm

- ❌ Commit file `.env` lên git
- ❌ Dùng `service_role` key trong frontend
- ❌ Tắt RLS để sửa lỗi nhanh
- ❌ Tạo policy `WITH CHECK (true)` cho mọi người

---

## 📋 Checklist kiểm thử bảo mật

| # | Test case | Cách kiểm tra | Kết quả mong đợi |
|---|-----------|---------------|------------------|
| 1 | Guest xem danh sách | Mở trang chủ | Thấy tất cả súng ✅ |
| 2 | Guest tìm kiếm | Nhập từ khóa | Lọc đúng kết quả ✅ |
| 3 | Guest sao chép code | Nhấn nút SAO CHÉP | Code được copy chính xác ✅ |
| 4 | Guest không thấy nút CRUD | Mở trang chủ | Không có nút thêm/sửa/xóa ✅ |
| 5 | Guest INSERT trực tiếp | Dùng Supabase JS SDK từ console | `policy violation` error ✅ |
| 6 | Guest UPDATE trực tiếp | Dùng Supabase JS SDK từ console | `policy violation` error ✅ |
| 7 | Guest DELETE trực tiếp | Dùng Supabase JS SDK từ console | `policy violation` error ✅ |
| 8 | Non-admin authenticated | Đăng nhập user thường, thử INSERT | Bị từ chối, redirect logout ✅ |
| 9 | Admin thêm súng | Vào admin, fill form | Súng xuất hiện ngay trên trang chủ ✅ |
| 10 | Admin sửa súng | Nhấn Sửa, cập nhật | Dữ liệu cập nhật đúng bản ghi ✅ |
| 11 | Admin xóa súng | Nhấn Xóa, xác nhận modal | Súng biến mất khỏi trang chủ ✅ |
| 12 | Đồng bộ real-time | Admin thêm, reload trang chủ | Dữ liệu mới xuất hiện ✅ |
| 13 | URL /admin/ khi chưa login | Truy cập trực tiếp URL | Redirect về login ✅ |
| 14 | Session hết hạn | Supabase tự revoke token | onAuthStateChange → redirect login ✅ |
| 15 | Anon key bị lộ | Dùng anon key để ghi dữ liệu | RLS chặn — an toàn ✅ |
| 16 | Không có secret trong source | Tìm kiếm trong dist/ | Chỉ có VITE_ vars công khai ✅ |

**Cách kiểm tra test 5-7 từ browser console:**
```javascript
// Mở trang chủ, mở DevTools console
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const sb = createClient('YOUR_URL', 'YOUR_ANON_KEY');
// Test INSERT bị chặn:
const { error } = await sb.from('weapon_codes').insert([{ weapon_name: 'hack', weapon_code: 'test' }]);
console.log(error); // → "new row violates row-level security policy"
```

---

## 📁 Cấu trúc dự án

```
bigshark-weapon-codes/
├── index.html                       # Trang chủ công khai
├── admin/
│   ├── login.html                   # Đăng nhập admin
│   └── index.html                   # Dashboard quản trị
├── src/
│   ├── css/
│   │   ├── main.css                 # Style trang chủ (dark gaming theme)
│   │   └── admin.css                # Style trang admin
│   └── js/
│       ├── supabase-client.js       # Khởi tạo Supabase client (anon key only)
│       ├── auth.js                  # getSession, isAdmin, signIn, signOut, requireAdmin
│       ├── weapon-codes.js          # fetchAll, search, getCount, copyCode (public)
│       └── admin.js                 # adminFetch, insert, update, delete (admin only)
├── supabase/
│   └── migrations/
│       ├── 001_initial_schema.sql
│       └── 002_community_submissions.sql   # Schema + RLS + triggers + policies
├── dist/                            # Build output (git-ignored)
├── .env.example                     # Mẫu biến môi trường
├── .env                             # Biến thực tế (KHÔNG commit)
├── .gitignore
├── package.json
├── vite.config.js
├── vercel.json
└── README.md
```

---

## 🔧 Quản lý Admin

### Thêm admin mới
```sql
-- Chạy trong Supabase SQL Editor
INSERT INTO public.admin_roles (user_id, granted_by)
VALUES ('uuid-của-user-mới', 'owner');
```

### Thu hồi quyền admin
```sql
DELETE FROM public.admin_roles WHERE user_id = 'uuid-cần-thu-hồi';
```

### Đổi mật khẩu admin
Vào **Supabase Dashboard → Authentication → Users** → chọn user → **Reset Password** (sẽ gửi email).

### Thêm tài khoản admin mới
Vào **Authentication → Users → Add user** → tạo xong → thêm UUID vào `admin_roles` như Bước 3.

---

## 🐛 Xử lý sự cố thường gặp

### Website báo "Supabase chưa được cấu hình"
→ Kiểm tra file `.env` có đúng hai biến `VITE_SUPABASE_URL` và `VITE_SUPABASE_ANON_KEY`

### Đăng nhập admin thành công nhưng bị redirect về login
→ Kiểm tra UUID trong bảng `admin_roles` có khớp với user đang đăng nhập không

### Lỗi khi chạy migration: `function gin_trgm_ops does not exist`
→ Vào **Database → Extensions** → bật `pg_trgm` trước rồi chạy lại migration

### Admin thêm súng được nhưng khách không thấy
→ Kiểm tra RLS policy `weapon_codes_public_select` đã áp dụng cho role `anon`

### Build lỗi trên Vercel
→ Đảm bảo đã thêm đúng biến môi trường trong Vercel project settings

---

*BIGSHARK WEAPON CODES — Dự án cộng đồng dành cho người chơi Delta Force. Không phải website chính thức của nhà phát hành.*
