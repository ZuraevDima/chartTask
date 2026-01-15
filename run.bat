@echo off
cd /d %~dp0

where node >nul 2>nul
if errorlevel 1 (
  echo Node.js не установлен
  pause
  exit
)

if not exist node_modules (
  echo Установка зависимостей...
  npm install
  if errorlevel 1 (
    echo Ошибка при установке зависимостей.
    pause
    exit
  )
)

echo Запуск dev-сервера и открытие браузера...
npm run dev -- --open

echo.
echo Нажмите любую клавишу для выхода...
pause >nul
