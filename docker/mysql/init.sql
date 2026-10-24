-- ============================================================
-- PROJECTWG DATABASE INITIALIZATION SCRIPT (MySQL 8.0)
-- File ini otomatis dieksekusi saat container MySQL pertama kali dibuat
-- ============================================================

-- Set Timezone default ke Asia/Jakarta (WIB UTC+7)
SET GLOBAL time_zone = '+07:00';
SET time_zone = '+07:00';

CREATE DATABASE IF NOT EXISTS `absensi_wg` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `absensi_wg`;

-- ------------------------------------------------------------
-- 1. TABEL ADMINS (Autentikasi Dashboard Website TSA)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `admins` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `username` VARCHAR(100) NOT NULL UNIQUE,
    `password` VARCHAR(255) NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `email` VARCHAR(150),
    `role` VARCHAR(50) DEFAULT 'Super Admin',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Akun default admin (admin / 123)
INSERT INTO `admins` (`id`, `username`, `password`, `name`, `email`, `role`)
VALUES (1, 'admin', '123', 'Administrator TSA', 'admin@tsa.co.id', 'Super Admin')
ON DUPLICATE KEY UPDATE `username` = VALUES(`username`);

-- ------------------------------------------------------------
-- 2. TABEL BRANCH_COMPANIES (Lokasi & Geofence Kantor Cabang)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `branch_companies` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `branch_name` VARCHAR(150) NOT NULL,
    `city` VARCHAR(100) NOT NULL,
    `latitude` DECIMAL(10, 8) NOT NULL,
    `longitude` DECIMAL(11, 8) NOT NULL,
    `radius` INT DEFAULT 150,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Data awal kantor cabang
INSERT INTO `branch_companies` (`id`, `branch_name`, `city`, `latitude`, `longitude`, `radius`)
VALUES 
(1, 'Kantor Pusat Surabaya', 'Surabaya', -7.25750000, 112.75210000, 200),
(2, 'Kantor Cabang Jakarta', 'Jakarta', -6.20880000, 106.84560000, 200)
ON DUPLICATE KEY UPDATE `branch_name` = VALUES(`branch_name`);

-- ------------------------------------------------------------
-- 3. TABEL USERS (Autentikasi Aplikasi Mobile Flutter & Referensi AI)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `users` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `username` VARCHAR(100) NOT NULL UNIQUE,
    `password` VARCHAR(255) NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `face_image` VARCHAR(255) NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 4. TABEL EMPLOYEES (Data Lengkap Karyawan)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employees` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `employee_id` VARCHAR(50) NOT NULL UNIQUE,
    `name` VARCHAR(150) NOT NULL,
    `team` VARCHAR(100) NOT NULL,
    `branch` VARCHAR(100) NOT NULL,
    `status` VARCHAR(50) NOT NULL DEFAULT 'Aktif',
    `tag1` VARCHAR(50) NULL,
    `tag2` VARCHAR(50) NULL,
    `tag3` VARCHAR(50) NULL,
    `username` VARCHAR(100) NOT NULL UNIQUE,
    `password` VARCHAR(255) NOT NULL,
    `face_image` VARCHAR(255) NULL,
    `email` VARCHAR(150) NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Data awal karyawan & user (sinkron dengan file fisik di assets/foto_karyawan/)
INSERT INTO `users` (`username`, `password`, `name`, `face_image`) VALUES
('satriya', '123', 'Satriya Putra', 'assets/foto_karyawan/821_677_22_Satriya.jpg'),
('aan', '123', 'Aan Handoko', 'assets/foto_karyawan/935_764_89_aan.jpg'),
('reva', '123', 'Reva Oktaviana', 'assets/foto_karyawan/616_860_35_reva.jpg'),
('ridho', '123', 'Ridho Ramadhan', 'assets/foto_karyawan/616_860_36_ridho.jpg'),
('rifky', '123', 'Rifky Hidayat', 'assets/foto_karyawan/665_394_19_rifky.jpg'),
('moh', '123', 'Mohammad Fajar', 'assets/foto_karyawan/799_362_33_moh.jpg'),
('raf', '123', 'Rafi Ahmad', 'assets/foto_karyawan/967_499_99_Raf.jpg'),
('rasyid', '123', 'Rasyid Ridha', 'assets/foto_karyawan/998_157_78_Rasyid.jpg')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

INSERT INTO `employees` (`employee_id`, `name`, `team`, `branch`, `status`, `tag1`, `tag2`, `tag3`, `username`, `password`, `face_image`, `email`) VALUES
('821.677.22', 'Satriya Putra', 'IT', 'Surabaya', 'Aktif', 'Full Time', 'On Site', 'Developer', 'satriya', '123', 'assets/foto_karyawan/821_677_22_Satriya.jpg', 'satriya@tsa.co.id'),
('935.764.89', 'Aan Handoko', 'HR', 'Surabaya', 'Aktif', 'Full Time', 'On Site', 'HR Staff', 'aan', '123', 'assets/foto_karyawan/935_764_89_aan.jpg', 'aan@tsa.co.id'),
('616.860.35', 'Reva Oktaviana', 'Operasional', 'Jakarta', 'Aktif', 'Full Time', 'On Site', 'Operations', 'reva', '123', 'assets/foto_karyawan/616_860_35_reva.jpg', 'reva@tsa.co.id'),
('616.860.36', 'Ridho Ramadhan', 'IT', 'Surabaya', 'Aktif', 'Full Time', 'Hybrid', 'Network Staff', 'ridho', '123', 'assets/foto_karyawan/616_860_36_ridho.jpg', 'ridho@tsa.co.id'),
('665.394.19', 'Rifky Hidayat', 'Keuangan', 'Surabaya', 'Aktif', 'Full Time', 'On Site', 'Finance Staff', 'rifky', '123', 'assets/foto_karyawan/665_394_19_rifky.jpg', 'rifky@tsa.co.id'),
('799.362.33', 'Mohammad Fajar', 'Marketing', 'Jakarta', 'Aktif', 'Full Time', 'Remote', 'Marketing Specialist', 'moh', '123', 'assets/foto_karyawan/799_362_33_moh.jpg', 'moh@tsa.co.id'),
('967.499.99', 'Rafi Ahmad', 'IT', 'Surabaya', 'Aktif', 'Contract', 'On Site', 'Junior Dev', 'raf', '123', 'assets/foto_karyawan/967_499_99_Raf.jpg', 'raf@tsa.co.id'),
('998.157.78', 'Rasyid Ridha', 'Operasional', 'Jakarta', 'Aktif', 'Part Time', 'On Site', 'Admin Staff', 'rasyid', '123', 'assets/foto_karyawan/998_157_78_Rasyid.jpg', 'rasyid@tsa.co.id')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- ------------------------------------------------------------
-- 5. TABEL ATTENDANCE (Presensi & Pengajuan Izin)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `attendance` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `username` VARCHAR(100) NOT NULL,
    `type` VARCHAR(50) NOT NULL,
    `timestamp` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `clock_out` DATETIME NULL,
    `image_path` VARCHAR(255) NULL,
    `reason` TEXT NULL,
    `status` VARCHAR(20) DEFAULT 'Pending',
    INDEX `idx_user_time` (`username`, `timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Contoh data absensi awal
INSERT INTO `attendance` (`username`, `type`, `timestamp`, `clock_out`, `reason`, `status`) VALUES
('satriya', 'clock_in', NOW() - INTERVAL 4 HOUR, NULL, NULL, 'Approved'),
('aan', 'izin', NOW() - INTERVAL 1 DAY, NULL, 'Izin menghadiri keperluan keluarga', 'Approved'),
('reva', 'sakit', NOW() - INTERVAL 2 DAY, NULL, 'Flu dan demam tinggi istirahat 1 hari', 'Approved')
ON DUPLICATE KEY UPDATE `username` = VALUES(`username`);

-- ------------------------------------------------------------
-- 6. TABEL VACANCIES (Lowongan Pekerjaan)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `vacancies` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `title` VARCHAR(150) NOT NULL,
    `division` VARCHAR(100) NOT NULL,
    `branch` VARCHAR(100) NOT NULL,
    `description` TEXT,
    `requirements` TEXT,
    `posted_date` DATE NOT NULL,
    `status` VARCHAR(50) DEFAULT 'Open',
    `image` VARCHAR(255) DEFAULT 'assets/avatar_mascot_centered.png',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Data awal lowongan kerja
INSERT INTO `vacancies` (`title`, `division`, `branch`, `description`, `requirements`, `posted_date`, `status`, `image`) VALUES
('Staff IT & Network', 'IT', 'Surabaya', 'Bertanggung jawab atas troubleshooting jaringan, pemeliharaan server, dan dukungan teknis harian bagi seluruh staf operasional kantor.', '- Pendidikan Min. D3/S1 Teknik Informatika / Sistem Informasi\n- Menguasai dasar routing, switching, dan Linux/Windows Server\n- Mampu bekerja dalam tim dan komunikasi baik\n- Bersedia on-site di Surabaya', '2026-10-10', 'Open', 'assets/avatar_mascot_centered.png'),
('Frontend Flutter Developer', 'IT', 'Jakarta', 'Mengembangkan dan merawat antarmuka aplikasi mobile absensi berbasis Flutter agar responsif, cepat, dan user friendly.', '- Pengalaman minimal 1 tahun menggunakan Flutter/Dart\n- Memahami integrasi REST API dan state management\n- Memiliki portofolio aplikasi mobile yang sudah dipublish merupakan nilai plus', '2026-10-12', 'Open', 'assets/avatar_mascot_centered.png'),
('Human Resource Specialist', 'HR', 'Surabaya', 'Mengelola rekrutmen karyawan baru, proses onboarding, serta memonitoring administrasi kehadiran dan kepatuhan SOP perusahaan.', '- Pendidikan S1 Psikologi / Manajemen SDM / Hukum\n- Pengalaman minimal 1 tahun di bidang HR / Rekrutmen\n- Memiliki kemampuan interpersonal yang tinggi', '2026-10-15', 'Open', 'assets/avatar_mascot_centered.png')
ON DUPLICATE KEY UPDATE `title` = VALUES(`title`);
