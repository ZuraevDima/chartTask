#!/usr/bin/env bash
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js не установлен. Установите Node.js и запустите снова."
  read -n1 -r -p "Нажмите любую клавишу для выхода..."
  exit 1
fi

if [ ! -d node_modules ]; then
  echo "Установка зависимостей..."
  npm install || { echo "Ошибка при установке зависимостей"; read -n1 -r -p "Нажмите любую клавишу для выхода..."; exit 1; }
fi

echo "Запуск dev-сервера и открытие браузера..."
npm run dev -- --open

echo
read -n1 -r -p "Нажмите любую клавишу для выхода..."
