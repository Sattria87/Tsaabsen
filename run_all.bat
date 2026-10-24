@echo off
chcp 65001 >nul
title ProjectWG - Master Runner (Backend, Website & AI)
cls
color 0b

echo ======================================================================
echo           🚀 MEMULAI SELURUH LAYANAN PROJECTWG (3-IN-1)
echo ======================================================================
echo.
echo [1/3] Menjalankan Backend Express API (Port 3000)...
start "ProjectWG - [1] Backend API (Port 3000)" cmd /k "cd /d "%~dp0backend" && npm start"

timeout /t 2 /nobreak >nul

echo [2/3] Menjalankan Website Admin TSA (Port 8085)...
start "ProjectWG - [2] Website Admin (Port 8085)" cmd /k "cd /d "%~dp0" && python admin_app.py"

timeout /t 2 /nobreak >nul

echo [3/3] Menjalankan AI Face Recognition Service (Port 5001)...
start "ProjectWG - [3] AI Service (Port 5001)" cmd /k "cd /d "%~dp0ai_service" && python app.py"

echo.
echo ======================================================================
echo  ✅ SEMUA SERVICE BERHASIL DIJALANKAN!
echo.
echo  📡 1. Backend Express API  : http://localhost:3000
echo  🌐 2. Website Admin TSA    : http://localhost:8085/login
echo  🧠 3. AI Face Recognition  : http://localhost:5001/health
echo ======================================================================
echo.
echo Tips: Anda bisa meminimalkan jendela ini.
echo Untuk mematikan salah satu service, cukup tutup jendela terminalnya masing-masing.
echo.
pause
