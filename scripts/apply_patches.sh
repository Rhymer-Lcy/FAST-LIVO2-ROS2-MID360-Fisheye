#!/usr/bin/env bash
# Накатывает все правки на свежесклонированный форк FAST-LIVO2-ROS2-MID360-Fisheye.
# Идемпотентен: повторный запуск ничего не ломает.
set -euo pipefail

PKG="${1:-$HOME/fast_ws/src/fast_livo}"
[ -d "$PKG" ] || { echo "Не найден пакет: $PKG"; exit 1; }
cd "$PKG"

say() { printf '\033[1;36m==> %s\033[0m\n' "$1"; }
skip() { printf '\033[0;33m    уже применено: %s\033[0m\n' "$1"; }

# 1. livox_ros_driver2 -> livox_interfaces
# Форк заточен под Livox-SDK2 (MID360/HAP), а Avia работает через SDK1.
# Определения CustomMsg побайтово совпадают, меняется только имя пакета.
if grep -rq livox_ros_driver2 src include CMakeLists.txt package.xml 2>/dev/null; then
  say "livox_ros_driver2 -> livox_interfaces"
  grep -rl livox_ros_driver2 src include CMakeLists.txt package.xml \
    | xargs sed -i 's/livox_ros_driver2/livox_interfaces/g'
else
  skip "livox_interfaces"
fi

# 2. exec_depend в package.xml (в оригинале объявлен только build_depend)
if ! grep -q '<exec_depend>livox_interfaces</exec_depend>' package.xml; then
  say "package.xml: добавляю exec_depend"
  sed -i 's|<build_depend>livox_interfaces</build_depend>|<build_depend>livox_interfaces</build_depend>\n  <exec_depend>livox_interfaces</exec_depend>|' package.xml
else
  skip "exec_depend"
fi

# 3. Глубина очередей.
# В ROS 1 subscribe(topic, 200000) — это потолок деки, ничего не стоит.
# В ROS 2 то же число становится History depth на уровне DDS: при отставании
# подписчика история растёт до 200000 сэмплов (480 КБ каждый у Avia) прежде
# чем что-то будет отброшено. На борту с малым ОЗУ это OOM вместо дропа кадров.
if grep -q '200000' src/LIVMapper.cpp; then
  say "глубина очередей: 200000 -> 10 / 2000 / 10"
  sed -i 's/(lid_topic, 200000,/(lid_topic, 10,/;
          s/(imu_topic, 200000,/(imu_topic, 2000,/;
          s/img_topic, 200000,/img_topic, 10,/' src/LIVMapper.cpp
else
  skip "глубина очередей"
fi

# 4. mapping_avia_marslvig.launch.py не передаёт ноде конфиг камеры:
# он уходит в parameter_blackboard, а vikit в этом форке читает параметры
# из самой ноды. Без правки — падение "Camera model not correctly specified."
L=launch/mapping_avia_marslvig.launch.py
# Проверка по количеству: в исходнике одно вхождение (в ноде parameter_blackboard),
# после патча их два. Проверять простым grep нельзя — он найдёт первое и решит,
# что патч уже наложен.
if [ -f "$L" ] && [ "$(grep -c 'camera_params_file,' "$L")" -lt 2 ]; then
  say "marslvig launch: передаю camera_params_file в ноду"
  sed -i 's/^\( *\)avia_params_file,$/\1avia_params_file,\n\1camera_params_file,/' "$L"
else
  skip "marslvig launch"
fi

# 5. Константы OpenCV 3 (CV_BGR2GRAY и т.п.). На Ubuntu 22.04 со штатным
# OpenCV 4.5 собирается и без этого; включается только если сборка упала.
if [ "${FIX_OPENCV:-0}" = "1" ] && ! grep -q 'imgproc/types_c.h' src/vio.cpp; then
  say "vio.cpp: legacy-заголовок OpenCV"
  sed -i '0,/#include/s//#include <opencv2\/imgproc\/types_c.h>\n#include/' src/vio.cpp
fi

# 6. Конфиги из configs/ в пакет
SRC_CFG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../configs" 2>/dev/null && pwd || true)"
if [ -n "$SRC_CFG" ] && [ -d "$SRC_CFG" ]; then
  say "копирую конфиги в $PKG/config"
  cp -v "$SRC_CFG"/*.yaml config/
fi

say "готово. Теперь: cd ~/fast_ws && colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release"
