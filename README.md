# ourbills — Minimal iOS Edition

Static site พร้อม Deploy บน Vercel ไม่มีขั้นตอน build และไม่ต้องตั้ง environment variables

## Deploy
1. แตก ZIP แล้วอัปโหลด **ไฟล์ทั้งหมดภายในโฟลเดอร์นี้** ไปยัง root ของ GitHub repository
2. Vercel → Add New Project → Import repository → Framework Preset: Other → Deploy
3. เปิด URL HTTPS บน Safari iPhone → Share → Add to Home Screen

## ไฟล์ไอคอน
- `icon.svg` ต้นฉบับเวกเตอร์ minimal
- `apple-touch-icon.png` 180×180 สำหรับ iPhone
- `icon-192.png`, `icon-512.png` และ `icon-maskable.png` สำหรับ PWA

## ข้อควรทราบ
ข้อมูลเก็บใน localStorage ของเบราว์เซอร์/อุปกรณ์นั้นเท่านั้น ยังไม่ซิงก์ข้ามเครื่อง และไม่มี OCR โปรด Export JSON สำรองข้อมูลสม่ำเสมอ

ไฟล์เวอร์ชันนี้ใช้ key ข้อมูลเดิม `ourbills_v2_data` เพื่อรักษาข้อมูลของ ourbills 2.0 บน origin เดิม
