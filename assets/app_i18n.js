/**
 * TSA Web Admin - Master Internationalization (i18n) Engine
 * Dukungan Bahasa: Bahasa Indonesia ('id') & English ('en')
 * Sinkronisasi otomatis ke semua menu, sub-menu, tab, tabel, tombol, modal, & status badge.
 */

(function () {
    const DICTIONARY = {
        id: {
            // ================= MENU SIDEBAR & LOGOUT =================
            menu_home: "Beranda",
            menu_employee: "Karyawan",
            menu_branch: "Kantor Cabang",
            menu_presence: "Kehadiran",
            menu_request: "Pengajuan Izin",
            menu_report: "Laporan",
            logout: "Keluar",
            logout_title: "Konfirmasi Logout",
            logout_msg: "Apakah Anda yakin ingin keluar dari Admin Dashboard TSA?",
            logout_cancel: "Batal",
            logout_confirm: "Ya, Keluar",
            back_btn: "Kembali",

            // ================= GREETING & WAKTU REALTIME =================
            greet_title: "Halo",
            greet_morning: "Selamat Pagi,",
            greet_afternoon: "Selamat Siang,",
            greet_evening: "Selamat Sore,",
            greet_night: "Selamat Malam,",
            days: ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"],
            months: ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"],

            // ================= HOMEPAGE =================
            home_metric_emp: "Karyawan",
            home_metric_pres: "Hadir Hari Ini",
            home_metric_abs: "Tidak Hadir Hari Ini",
            home_metric_req: "Pengajuan Izin / Sakit",
            home_chart_title: "Statistik Kehadiran Bulanan",
            home_chart_badge: "Rekapitulasi Tahun Berjalan",
            home_quick_title: "Aktivitas Presensi Terkini",
            home_quick_unit: "Karyawan",
            home_quick_empty: "Belum ada riwayat aktivitas presensi karyawan hari ini.",
            chart_lbl_emp: "Karyawan",
            chart_lbl_pres: "Hadir",
            chart_lbl_abs: "Tidak Hadir",

            // ================= EMPLOYEE (MANAJEMEN KARYAWAN) =================
            emp_mgmt_title: "Manajemen Data Karyawan",
            emp_header_title: "Data Karyawan",
            emp_breadcrumb: "Employee / Data Karyawan & Acuan AI Face Recognition",
            emp_btn_register: "Tambah Karyawan",
            emp_search_placeholder: "Cari nama karyawan, NIP, atau divisi...",
            emp_search_btn: "Cari",
            emp_reset_btn: "Reset",
            emp_th_photo_name: "Foto & Nama",
            emp_th_id: "ID Karyawan",
            emp_th_division: "Divisi",
            emp_th_branch: "Kantor Cabang",
            emp_th_status: "Status",
            emp_th_ai: "Acuan AI",
            emp_th_action: "Aksi",
            emp_btn_detail: "Detail",
            emp_btn_delete: "Hapus",
            emp_delete_confirm: "Apakah Anda yakin ingin menghapus data karyawan ini?",
            emp_empty: "Tidak ada data karyawan yang ditemukan.",

            // MODAL TAMBAH KARYAWAN
            emp_modal_title: "Tambah Karyawan Baru",
            emp_modal_subtitle: "Daftarkan akun login dan foto acuan AI Face Recognition",
            emp_sec_profile: "Informasi Profil Karyawan",
            emp_sec_account: "Akun Login Aplikasi Flutter",
            emp_sec_camera: "Foto Selfie Kamera (Acuan AI)",
            emp_lbl_name: "Nama Lengkap",
            emp_lbl_division: "Divisi",
            emp_lbl_branch: "Kantor Cabang",
            emp_lbl_status: "Status Kepegawaian",
            emp_lbl_username: "Username",
            emp_lbl_password: "Password",
            emp_ph_name: "Contoh: Susi Febriani",
            emp_ph_division: "Contoh: HR / IT / Marketing",
            emp_ph_username: "Contoh: susi123",
            emp_ph_password: "Password akun",
            emp_camera_guide: "Wajah harus terlihat jelas, tegak lurus, dan menghadap kamera untuk master acuan AI.",
            emp_camera_placeholder: "Kamera belum aktif.<br>Klik tombol <strong>Buka Kamera</strong> di bawah.",
            emp_camera_status_inactive: "Kamera dalam keadaan non-aktif",
            emp_camera_status_active: "Kamera aktif - Posisikan wajah di tengah",
            emp_camera_status_captured: "Foto berhasil diambil!",
            emp_btn_open_cam: "Buka Kamera",
            emp_btn_capture: "Ambil Foto",
            emp_btn_retake: "Foto Ulang",
            emp_lbl_upload_file: "Opsi unggah file foto wajah:",
            emp_warn_face_required: "Foto selfie wajah wajib diambil sebagai acuan AI sebelum menyimpan!",
            emp_btn_cancel: "Batal",
            emp_btn_save: "Simpan Karyawan",
            emp_face_oval_text: "POSISIKAN WAJAH",

            // ================= EMPLOYEE DETAIL =================
            emp_det_back: "Kembali ke Data Karyawan",
            emp_det_top_title: "Detail Aktivitas Karyawan",
            emp_det_dashboard: "Beranda",
            emp_det_ai_badge: "Acuan AI Face Recognition",
            emp_det_user_mobile: "Username Mobile:",
            emp_det_pass_acc: "Password Akun:",
            emp_det_team: "Tim / Divisi:",
            emp_det_branch: "Kantor Cabang:",
            emp_det_stat_present: "Total Hadir",
            emp_det_stat_ontime: "Tepat Waktu",
            emp_det_stat_late: "Terlambat",
            emp_det_stat_leave: "Total Izin / Sakit",
            emp_det_tab_summary: "Ringkasan",
            emp_det_tab_presence: "Kehadiran",
            emp_det_tab_leave: "Pengajuan Izin & Sakit",
            emp_det_tab_all: "Semua Aktivitas",
            emp_det_info_title: "Informasi Pribadi & Kontak",
            emp_det_fullname: "Nama Lengkap",
            emp_det_phone: "Nomor Telepon",
            emp_det_email: "Alamat Email",
            emp_det_join: "Bergabung Sejak",
            emp_det_recent_title: "Aktivitas Presensi Terakhir",
            emp_det_empty_presence: "Belum ada riwayat kehadiran tercatat.",
            emp_det_empty_leave: "Belum ada riwayat pengajuan izin atau sakit.",
            emp_det_empty_all: "Belum ada riwayat aktivitas yang tercatat untuk karyawan ini.",

            // ================= BRANCH COMPANY =================
            branch_mgmt_title: "Manajemen Kantor Cabang",
            branch_header_title: "Kantor Cabang",
            branch_breadcrumb: "Branch company / Manajemen Lokasi & Radius Absensi GPS",
            branch_btn_add: "Tambah Cabang",
            branch_search_placeholder: "Cari nama cabang atau kota...",
            branch_th_name: "Nama Cabang",
            branch_th_city: "Kota / Wilayah",
            branch_th_coord: "Koordinat GPS",
            branch_th_radius: "Radius Presensi",
            branch_th_action: "Aksi",
            branch_empty: "Belum ada data kantor cabang. Klik Tambah Cabang untuk menambahkan.",
            branch_modal_add_title: "Tambah Kantor Cabang Baru",
            branch_modal_add_sub: "Isi koordinat GPS dan radius absensi",
            branch_modal_edit_title: "Edit Kantor Cabang",
            branch_lbl_name: "Nama Cabang",
            branch_lbl_city: "Kota",
            branch_lbl_lat: "Latitude",
            branch_lbl_lng: "Longitude",
            branch_lbl_radius: "Radius Validasi Absen (Meter)",
            branch_hint_radius: "Jarak maksimal karyawan dari kantor saat absen (dalam meter).",
            branch_gps_title: "Ambil Koordinat GPS Saat Ini",
            branch_gps_btn: "Gunakan Lokasi Saya Sekarang",
            branch_btn_save: "Simpan Cabang",
            branch_btn_update: "Simpan Perubahan",

            // ================= PRESENCE (KEHADIRAN) =================
            pres_banner_title: "Kehadiran",
            pres_page_title: "Kehadiran Karyawan",
            pres_breadcrumb: "Presence / Overview Aktivitas Presensi Harian",
            pres_tab_all: "Semua",
            pres_tab_present: "Hadir",
            pres_tab_leave: "Izin / Sakit",
            pres_tab_absent: "Belum Hadir",
            pres_search_placeholder: "Cari nama, NIP, atau divisi...",
            pres_filter_btn: "Filter",
            pres_reset_btn: "Reset",
            pres_th_no: "No",
            pres_th_emp: "Karyawan",
            pres_th_in: "Jam Masuk",
            pres_th_out: "Jam Keluar",
            pres_th_method: "Metode / Lokasi",
            pres_th_status: "Status Kehadiran",
            pres_th_action: "Aksi",
            pres_btn_detail: "Detail",
            pres_empty: "Tidak ada data presensi yang sesuai dengan kriteria pencarian.",
            pres_modal_detail_title: "Detail Presensi Karyawan",
            pres_modal_lbl_name: "Nama Karyawan",
            pres_modal_lbl_div: "Divisi",
            pres_modal_lbl_date: "Tanggal",
            pres_modal_lbl_in: "Waktu Masuk",
            pres_modal_lbl_out: "Waktu Keluar",
            pres_modal_lbl_loc: "Lokasi Presensi",
            pres_modal_lbl_photo: "Foto Verifikasi Wajah",
            pres_modal_close: "Tutup",

            // ================= REQUEST (PENGAJUAN IZIN) =================
            req_banner_title: "Pengajuan Izin",
            req_page_title: "Data Pengajuan Izin / Sakit",
            req_breadcrumb: "Request / Data Pengajuan Izin Sakit",
            req_btn_create: "Ajukan Izin / Sakit",
            req_tab_pending: "Pending",
            req_tab_approved: "Disetujui",
            req_tab_rejected: "Ditolak",
            req_tab_all: "Semua Data",
            req_th_emp_reason: "Karyawan & Keperluan",
            req_th_date: "Tanggal",
            req_th_division: "Divisi",
            req_th_branch: "Cabang",
            req_th_status: "Status",
            req_th_action: "Aksi",
            req_btn_approve: "Setujui",
            req_btn_reject: "Tolak",
            req_btn_detail: "Detail",
            req_btn_delete: "Hapus",
            req_confirm_delete: "Yakin ingin menghapus data pengajuan ini?",
            req_empty_pending: "Tidak ada pengajuan yang menunggu persetujuan.",
            req_empty_approved: "Belum ada pengajuan yang disetujui.",
            req_empty_rejected: "Tidak ada pengajuan yang ditolak.",
            req_empty_all: "Belum ada riwayat pengajuan izin/sakit.",
            req_modal_add_title: "Form Pengajuan Izin / Sakit",
            req_modal_add_sub: "Isi data formulir pengajuan izin atau sakit untuk karyawan",
            req_lbl_emp_select: "Pilih Karyawan",
            req_lbl_type: "Tipe Pengajuan",
            req_opt_sick: "Sakit (Surat Dokter)",
            req_opt_leave: "Izin / Keperluan Mendesak",
            req_opt_annual: "Cuti Tahunan",
            req_lbl_date: "Tanggal Izin",
            req_lbl_duration: "Durasi (Hari)",
            req_lbl_reason: "Alasan / Keperluan",
            req_ph_reason: "Jelaskan alasan pengajuan izin atau sakit...",
            req_lbl_attachment: "Lampiran Surat Dokter / Bukti",
            req_btn_submit: "Kirim Pengajuan",
            req_modal_detail_title: "Detail Pengajuan Izin / Sakit",
            req_modal_detail_emp: "Karyawan",
            req_modal_detail_type: "Jenis Pengajuan",
            req_modal_detail_date: "Tanggal",
            req_modal_detail_reason: "Alasan Lengkap",
            req_modal_detail_status: "Status Pengajuan",
            req_modal_detail_doc: "Dokumen Lampiran",

            // ================= REPORT (LAPORAN) =================
            rep_banner_title: "Laporan",
            rep_page_title: "Export Laporan Kehadiran",
            rep_breadcrumb: "Report / Export Laporan Kehadiran",
            rep_card_title: "Pengaturan Laporan",
            rep_lbl_range: "Rentang tanggal",
            rep_lbl_to: "s/d",
            rep_lbl_branch: "Kantor Cabang",
            rep_opt_all_branches: "Semua Kantor Cabang",
            rep_lbl_format: "Format File",
            rep_opt_excel: ".XLSX (Excel Spreadsheet)",
            rep_opt_pdf: ".PDF (Dokumen PDF)",
            rep_btn_generate: "Generate Laporan",

            // ================= LOGIN PAGE =================
            login_card_subtitle: "Sistem Administrasi Presensi & AI TSA",
            login_lbl_username: "Username",
            login_lbl_password: "Password",
            login_ph_username: "Masukkan username admin",
            login_ph_password: "Masukkan password",
            login_remember: "Ingat saya",
            login_forgot: "Lupa kata sandi?",
            login_btn: "Masuk",
            login_modal_title: "Reset Password Admin",
            login_modal_desc: "Untuk alasan keamanan sistem, pengaturan ulang kata sandi admin hanya dapat dilakukan oleh Super Admin melalui database atau hubungi tim IT di admin@tsa.co.id.",
            login_modal_close: "Mengerti",

            // ================= STATUS & BADGES UMUM =================
            status_active: "Aktif",
            status_inactive: "Nonaktif",
            status_approved: "Disetujui",
            status_rejected: "Ditolak",
            status_pending: "Pending",
            status_present: "Hadir",
            status_absent: "Belum Hadir",
            status_leave: "Izin",
            status_sick: "Sakit",
            status_ontime: "Tepat Waktu",
            status_late: "Terlambat",
            status_registered: "Terdaftar",
            status_unregistered: "Belum Terdaftar"
        },

        en: {
            // ================= MENU SIDEBAR & LOGOUT =================
            menu_home: "Home page",
            menu_employee: "Employee",
            menu_branch: "Branch company",
            menu_presence: "Presence",
            menu_request: "Request",
            menu_report: "Report",
            logout: "Logout",
            logout_title: "Logout Confirmation",
            logout_msg: "Are you sure you want to log out of the TSA Admin Dashboard?",
            logout_cancel: "Cancel",
            logout_confirm: "Yes, Logout",
            back_btn: "Back",

            // ================= GREETING & WAKTU REALTIME =================
            greet_title: "Hello",
            greet_morning: "Good Morning,",
            greet_afternoon: "Good Afternoon,",
            greet_evening: "Good Evening,",
            greet_night: "Good Evening,",
            days: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
            months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],

            // ================= HOMEPAGE =================
            home_metric_emp: "Employees",
            home_metric_pres: "Present Today",
            home_metric_abs: "Absent Today",
            home_metric_req: "Leave / Sick Requests",
            home_chart_title: "Monthly Attendance Statistics",
            home_chart_badge: "Current Year Recapitulation",
            home_quick_title: "Recent Attendance Activity",
            home_quick_unit: "Employees",
            home_quick_empty: "No employee attendance activity recorded today.",
            chart_lbl_emp: "Employees",
            chart_lbl_pres: "Presence",
            chart_lbl_abs: "Absence",

            // ================= EMPLOYEE (MANAJEMEN KARYAWAN) =================
            emp_mgmt_title: "Employee Management",
            emp_header_title: "Employee Directory",
            emp_breadcrumb: "Employee / Directory & AI Face Recognition Reference",
            emp_btn_register: "Register Employee",
            emp_search_placeholder: "Search employee by name, ID, or division...",
            emp_search_btn: "Search",
            emp_reset_btn: "Reset",
            emp_th_photo_name: "Photo & Name",
            emp_th_id: "Employee ID",
            emp_th_division: "Division",
            emp_th_branch: "Branch Office",
            emp_th_status: "Status",
            emp_th_ai: "AI Reference",
            emp_th_action: "Action",
            emp_btn_detail: "Detail",
            emp_btn_delete: "Delete",
            emp_delete_confirm: "Are you sure you want to delete this employee record?",
            emp_empty: "No employee records found.",

            // MODAL TAMBAH KARYAWAN
            emp_modal_title: "Register New Employee",
            emp_modal_subtitle: "Create login account and register master AI face recognition reference",
            emp_sec_profile: "Employee Profile Information",
            emp_sec_account: "Flutter App Login Account",
            emp_sec_camera: "Camera Selfie Photo (AI Reference)",
            emp_lbl_name: "Full Name",
            emp_lbl_division: "Division",
            emp_lbl_branch: "Branch Office",
            emp_lbl_status: "Employment Status",
            emp_lbl_username: "Username",
            emp_lbl_password: "Password",
            emp_ph_name: "E.g., Sarah Jenkins",
            emp_ph_division: "E.g., HR / IT / Marketing",
            emp_ph_username: "E.g., sarah123",
            emp_ph_password: "Account password",
            emp_camera_guide: "Face must be clearly visible, straight, and centered to serve as the master AI reference.",
            emp_camera_placeholder: "Camera is not active.<br>Click the <strong>Open Camera</strong> button below.",
            emp_camera_status_inactive: "Camera is currently inactive",
            emp_camera_status_active: "Camera active - Center your face inside the frame",
            emp_camera_status_captured: "Photo captured successfully!",
            emp_btn_open_cam: "Open Camera",
            emp_btn_capture: "Take Photo",
            emp_btn_retake: "Retake Photo",
            emp_lbl_upload_file: "Or upload face photo file:",
            emp_warn_face_required: "Camera selfie photo is required as AI reference before saving!",
            emp_btn_cancel: "Cancel",
            emp_btn_save: "Save Employee",
            emp_face_oval_text: "POSITION FACE",

            // ================= EMPLOYEE DETAIL =================
            emp_det_back: "Back to Employees",
            emp_det_top_title: "Employee Activity Details",
            emp_det_dashboard: "Dashboard",
            emp_det_ai_badge: "AI Face Recognition Reference",
            emp_det_user_mobile: "Mobile Username:",
            emp_det_pass_acc: "Account Password:",
            emp_det_team: "Team / Division:",
            emp_det_branch: "Branch Office:",
            emp_det_stat_present: "Total Present",
            emp_det_stat_ontime: "On Time",
            emp_det_stat_late: "Late",
            emp_det_stat_leave: "Total Leave / Sick",
            emp_det_tab_summary: "Summary",
            emp_det_tab_presence: "Attendance",
            emp_det_tab_leave: "Leave & Sick Requests",
            emp_det_tab_all: "All Activities",
            emp_det_info_title: "Personal & Contact Information",
            emp_det_fullname: "Full Name",
            emp_det_phone: "Phone Number",
            emp_det_email: "Email Address",
            emp_det_join: "Joined Since",
            emp_det_recent_title: "Recent Attendance Activity",
            emp_det_empty_presence: "No attendance history recorded yet.",
            emp_det_empty_leave: "No leave or sick requests recorded.",
            emp_det_empty_all: "No activity records found for this employee.",

            // ================= BRANCH COMPANY =================
            branch_mgmt_title: "Branch Company Management",
            branch_header_title: "Branch Offices",
            branch_breadcrumb: "Branch company / GPS Location & Presence Radius Management",
            branch_btn_add: "Add Branch",
            branch_search_placeholder: "Search branch name or city...",
            branch_th_name: "Branch Name",
            branch_th_city: "City / Region",
            branch_th_coord: "GPS Coordinates",
            branch_th_radius: "Presence Radius",
            branch_th_action: "Action",
            branch_empty: "No branch office data yet. Click Add Branch to create one.",
            branch_modal_add_title: "Add New Branch Office",
            branch_modal_add_sub: "Specify GPS coordinates and attendance radius",
            branch_modal_edit_title: "Edit Branch Office",
            branch_lbl_name: "Branch Name",
            branch_lbl_city: "City",
            branch_lbl_lat: "Latitude",
            branch_lbl_lng: "Longitude",
            branch_lbl_radius: "Presence Validation Radius (Meters)",
            branch_hint_radius: "Maximum distance employees can be from office when clocking in (in meters).",
            branch_gps_title: "Get Current GPS Coordinates",
            branch_gps_btn: "Use My Current Location",
            branch_btn_save: "Save Branch",
            branch_btn_update: "Save Changes",

            // ================= PRESENCE (KEHADIRAN) =================
            pres_banner_title: "Presence",
            pres_page_title: "Employee Presence",
            pres_breadcrumb: "Presence / Daily Employee Attendance Overview",
            pres_tab_all: "All",
            pres_tab_present: "Present",
            pres_tab_leave: "Leave / Sick",
            pres_tab_absent: "Absent",
            pres_search_placeholder: "Search by name, employee ID, or division...",
            pres_filter_btn: "Filter",
            pres_reset_btn: "Reset",
            pres_th_no: "No",
            pres_th_emp: "Employee",
            pres_th_in: "Clock In",
            pres_th_out: "Clock Out",
            pres_th_method: "Method / Location",
            pres_th_status: "Attendance Status",
            pres_th_action: "Action",
            pres_btn_detail: "Detail",
            pres_empty: "No attendance records match your search criteria.",
            pres_modal_detail_title: "Employee Attendance Details",
            pres_modal_lbl_name: "Employee Name",
            pres_modal_lbl_div: "Division",
            pres_modal_lbl_date: "Date",
            pres_modal_lbl_in: "Clock In Time",
            pres_modal_lbl_out: "Clock Out Time",
            pres_modal_lbl_loc: "Attendance Location",
            pres_modal_lbl_photo: "Face Verification Photo",
            pres_modal_close: "Close",

            // ================= REQUEST (PENGAJUAN IZIN) =================
            req_banner_title: "Request",
            req_page_title: "Leave & Sick Requests",
            req_breadcrumb: "Request / Leave & Sick Permission Records",
            req_btn_create: "Apply Leave / Sick",
            req_tab_pending: "Pending",
            req_tab_approved: "Approved",
            req_tab_rejected: "Rejected",
            req_tab_all: "All Data",
            req_th_emp_reason: "Employee & Purpose",
            req_th_date: "Date",
            req_th_division: "Division",
            req_th_branch: "Branch",
            req_th_status: "Status",
            req_th_action: "Action",
            req_btn_approve: "Approve",
            req_btn_reject: "Reject",
            req_btn_detail: "Detail",
            req_btn_delete: "Delete",
            req_confirm_delete: "Are you sure you want to delete this request record?",
            req_empty_pending: "No pending requests awaiting approval.",
            req_empty_approved: "No approved requests yet.",
            req_empty_rejected: "No rejected requests.",
            req_empty_all: "No leave or sick requests recorded.",
            req_modal_add_title: "Leave & Sick Request Form",
            req_modal_add_sub: "Submit a new leave or sick permission request for employee",
            req_lbl_emp_select: "Select Employee",
            req_lbl_type: "Request Type",
            req_opt_sick: "Sick (Doctor's Note)",
            req_opt_leave: "Permission / Urgent Leave",
            req_opt_annual: "Annual Leave",
            req_lbl_date: "Leave Date",
            req_lbl_duration: "Duration (Days)",
            req_lbl_reason: "Reason / Purpose",
            req_ph_reason: "Describe the reason for leave or sickness...",
            req_lbl_attachment: "Doctor's Note / Proof Document",
            req_btn_submit: "Submit Request",
            req_modal_detail_title: "Leave & Sick Request Details",
            req_modal_detail_emp: "Employee",
            req_modal_detail_type: "Request Type",
            req_modal_detail_date: "Date",
            req_modal_detail_reason: "Full Reason",
            req_modal_detail_status: "Request Status",
            req_modal_detail_doc: "Attached Document",

            // ================= REPORT (LAPORAN) =================
            rep_banner_title: "Report",
            rep_page_title: "Export Attendance Reports",
            rep_breadcrumb: "Report / Export Attendance Reports",
            rep_card_title: "Report Settings",
            rep_lbl_range: "Date Range",
            rep_lbl_to: "to",
            rep_lbl_branch: "Branch Office",
            rep_opt_all_branches: "All Branch Offices",
            rep_lbl_format: "File Format",
            rep_opt_excel: ".XLSX (Excel Spreadsheet)",
            rep_opt_pdf: ".PDF (PDF Document)",
            rep_btn_generate: "Generate Report",

            // ================= LOGIN PAGE =================
            login_card_subtitle: "TSA Attendance & AI Administration System",
            login_lbl_username: "Username",
            login_lbl_password: "Password",
            login_ph_username: "Enter admin username",
            login_ph_password: "Enter password",
            login_remember: "Remember me",
            login_forgot: "Forgot password?",
            login_btn: "Login",
            login_modal_title: "Reset Admin Password",
            login_modal_desc: "For system security reasons, resetting admin credentials must be performed by Super Admin via database or by contacting the IT department at admin@tsa.co.id.",
            login_modal_close: "Understood",

            // ================= STATUS & BADGES UMUM =================
            status_active: "Active",
            status_inactive: "Inactive",
            status_approved: "Approved",
            status_rejected: "Rejected",
            status_pending: "Pending",
            status_present: "Present",
            status_absent: "Absent",
            status_leave: "Leave",
            status_sick: "Sick",
            status_ontime: "On Time",
            status_late: "Late",
            status_registered: "Registered",
            status_unregistered: "Not Registered"
        }
    };

    /**
     * Dapatkan bahasa tersimpan saat ini ('id' atau 'en')
     */
    function getCurrentLanguage() {
        return localStorage.getItem('admin_lang') || 'id';
    }

    /**
     * Ganti bahasa global dan terapkan ke DOM
     */
    function changeLanguage(lang) {
        if (lang !== 'id' && lang !== 'en') lang = 'id';
        localStorage.setItem('admin_lang', lang);
        applyLanguage(lang);
    }

    /**
     * Format tanggal dinamis realtime sesuai bahasa
     */
    function getFormattedDate(lang) {
        const now = new Date();
        const t = DICTIONARY[lang] || DICTIONARY.id;
        const day = t.days[now.getDay()];
        const month = t.months[now.getMonth()];
        const date = now.getDate();
        const year = now.getFullYear();

        if (lang === 'id') {
            return {
                dayName: day,
                fullDate: `${date} ${month} ${year}`,
                display: `${day}, ${date} ${month} ${year}`
            };
        } else {
            return {
                dayName: day,
                fullDate: `${month} ${date}, ${year}`,
                display: `${day}, ${month} ${date}, ${year}`
            };
        }
    }

    /**
     * Terapkan terjemahan ke seluruh elemen halaman
     */
    function applyLanguage(lang) {
        if (!lang) lang = getCurrentLanguage();
        document.documentElement.lang = lang;
        const t = DICTIONARY[lang] || DICTIONARY.id;

        // 1. Perbarui state tombol pemilih bahasa (.lang-btn)
        document.querySelectorAll('.lang-btn').forEach(btn => {
            if (btn.getAttribute('data-lang') === lang) {
                btn.classList.add('active');
            } else {
                btn.classList.remove('active');
            }
        });

        // 2. Terjemahkan elemen berbasis attribute [data-i18n]
        document.querySelectorAll('[data-i18n]').forEach(el => {
            const key = el.getAttribute('data-i18n');
            if (t[key] !== undefined) {
                el.textContent = t[key];
            }
        });

        // 3. Terjemahkan elemen berbasis attribute [data-i18n-html]
        document.querySelectorAll('[data-i18n-html]').forEach(el => {
            const key = el.getAttribute('data-i18n-html');
            if (t[key] !== undefined) {
                el.innerHTML = t[key];
            }
        });

        // 4. Terjemahkan placeholder form [data-i18n-placeholder]
        document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
            const key = el.getAttribute('data-i18n-placeholder');
            if (t[key] !== undefined) {
                el.placeholder = t[key];
            }
        });

        // 5. Terjemahkan title attribute [data-i18n-title]
        document.querySelectorAll('[data-i18n-title]').forEach(el => {
            const key = el.getAttribute('data-i18n-title');
            if (t[key] !== undefined) {
                el.title = t[key];
            }
        });

        // 6. Terjemahkan Sidebar Menu Standar
        const navMap = [
            { sel: 'a[href="/"].side-btn, #menu-home', text: t.menu_home },
            { sel: 'a[href="/employee"].side-btn, #menu-employee', text: t.menu_employee },
            { sel: 'a[href="/branch-company"].side-btn, #menu-branch', text: t.menu_branch },
            { sel: 'a[href="/presence"].side-btn, #menu-presence', text: t.menu_presence },
            { sel: 'a[href="/request"].side-btn, #menu-request', text: t.menu_request },
            { sel: 'a[href="/report"].side-btn, #menu-report', text: t.menu_report },
            { sel: '.logout-btn, #btn-logout', text: t.logout }
        ];
        navMap.forEach(item => {
            document.querySelectorAll(item.sel).forEach(el => {
                el.textContent = item.text;
            });
        });

        // 7. Terjemahkan Top Navbar Waktu & Realtime Clock
        const dateObj = getFormattedDate(lang);
        const clockEls = document.querySelectorAll('.realtime-clock, #realtime-clock, .navbar-date-section');
        clockEls.forEach(el => {
            el.textContent = dateObj.display;
        });

        const dayBadge = document.getElementById('current-day-label');
        if (dayBadge) dayBadge.textContent = dateObj.dayName;
        const dateBadge = document.getElementById('current-date-badge');
        if (dateBadge) dateBadge.textContent = dateObj.fullDate;

        // 8. Terjemahkan Greeting Header (Homepage)
        const greetTitle = document.getElementById('greeting-title');
        if (greetTitle) greetTitle.textContent = t.greet_title;

        const greetSub = document.getElementById('greeting-subtitle');
        if (greetSub) {
            const hour = new Date().getHours();
            if (lang === 'id') {
                if (hour >= 4 && hour < 11) greetSub.textContent = t.greet_morning;
                else if (hour >= 11 && hour < 15) greetSub.textContent = t.greet_afternoon;
                else if (hour >= 15 && hour < 18) greetSub.textContent = t.greet_evening;
                else greetSub.textContent = t.greet_night;
            } else {
                if (hour >= 4 && hour < 12) greetSub.textContent = t.greet_morning;
                else if (hour >= 12 && hour < 18) greetSub.textContent = t.greet_afternoon;
                else greetSub.textContent = t.greet_evening;
            }
        }

        // 9. Terjemahkan Modal Logout
        const logoutTitle = document.getElementById('logout-title');
        if (logoutTitle) logoutTitle.textContent = t.logout_title;
        const logoutMsg = document.getElementById('logout-msg');
        if (logoutMsg) logoutMsg.textContent = t.logout_msg;
        const logoutCancel = document.getElementById('logout-btn-cancel');
        if (logoutCancel) logoutCancel.textContent = t.logout_cancel;
        const logoutConfirm = document.getElementById('logout-btn-confirm');
        if (logoutConfirm) logoutConfirm.textContent = t.logout_confirm;

        // 10. Terjemahkan Chart Legends (Homepage jika ada)
        try {
            if (window.monthlyChart && window.monthlyChart.data && window.monthlyChart.data.datasets && window.monthlyChart.data.datasets.length >= 3) {
                window.monthlyChart.data.datasets[0].label = t.chart_lbl_emp;
                window.monthlyChart.data.datasets[1].label = t.chart_lbl_pres;
                window.monthlyChart.data.datasets[2].label = t.chart_lbl_abs;
                window.monthlyChart.update();
            }
        } catch(chartErr) {
            console.warn("monthlyChart update skipped:", chartErr);
        }

        // 11. Terjemahkan Dynamic Badges (Status Pills)
        try {
            document.querySelectorAll('.tag-pill-approved, .badge-approved').forEach(el => {
                el.innerHTML = `<i class="bi bi-check-circle-fill" style="font-size: 11px;"></i> ${t.status_approved}`;
            });
            document.querySelectorAll('.tag-pill-rejected, .badge-rejected').forEach(el => {
                el.innerHTML = `<i class="bi bi-x-circle-fill" style="font-size: 11px;"></i> ${t.status_rejected}`;
            });
            document.querySelectorAll('.tag-pill-pending, .badge-pending').forEach(el => {
                el.innerHTML = `<i class="bi bi-hourglass-split" style="font-size: 11px;"></i> ${t.status_pending}`;
            });

            // Dynamic Status Badges di Presence / Employee
            document.querySelectorAll('.badge-status-item').forEach(el => {
                const rawStatus = (el.getAttribute('data-status-type') || '').toLowerCase();
                if (rawStatus === 'hadir' || rawStatus === 'present') el.textContent = t.status_present;
                else if (rawStatus === 'izin' || rawStatus === 'leave') el.textContent = t.status_leave;
                else if (rawStatus === 'sakit' || rawStatus === 'sick') el.textContent = t.status_sick;
                else if (rawStatus === 'belum' || rawStatus === 'absent') el.textContent = t.status_absent;
                else if (rawStatus === 'active' || rawStatus === 'aktif') el.textContent = t.status_active;
                else if (rawStatus === 'inactive' || rawStatus === 'nonaktif') el.textContent = t.status_inactive;
            });
        } catch(badgeErr) {
            console.warn("Badge status update skipped:", badgeErr);
        }

        // Trigger custom event untuk perbaikan spesifik per-halaman jika dibutuhkan
        try {
            window.dispatchEvent(new CustomEvent('appLanguageChanged', { detail: { lang, t } }));
        } catch(e) {}
    }

    // Ekspor API Global
    window.AppI18n = {
        dict: DICTIONARY,
        getLang: getCurrentLanguage,
        setLang: changeLanguage,
        apply: applyLanguage,
        t: function(key) {
            const lang = getCurrentLanguage();
            return (DICTIONARY[lang] && DICTIONARY[lang][key]) || (DICTIONARY.id && DICTIONARY.id[key]) || key;
        }
    };

    // Buat alias global changeLanguage untuk backward compatibility dengan onclick="changeLanguage('...')"
    window.changeLanguage = changeLanguage;

    // Event listener delegasi global: pastikan klik pada tombol bahasa (.lang-btn) selalu berjalan
    document.addEventListener('click', function(e) {
        const btn = e.target && e.target.closest && e.target.closest('.lang-btn');
        if (btn) {
            e.preventDefault();
            const lang = btn.getAttribute('data-lang');
            if (lang) {
                changeLanguage(lang);
            }
        }
    }, true);

    // Inisialisasi otomatis saat DOM siap
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => applyLanguage(getCurrentLanguage()));
    } else {
        applyLanguage(getCurrentLanguage());
    }
})();
