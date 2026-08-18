#!/usr/bin/env bash
# Конвертирует ROS 1 бэг в ROS 2 и чинит metadata.yaml под Humble.
#   ./prepare_bag.sh ~/datasets/Retail_Street.bag
set -euo pipefail

SRC="${1:?использование: $0 <файл.bag> [каталог назначения]}"
DST="${2:-${SRC%.bag}}"
CONV="${ROSBAGS_CONVERT:-$HOME/venv-rosbags/bin/rosbags-convert}"

[ -f "$SRC" ] || { echo "Нет файла: $SRC"; exit 1; }
[ -x "$CONV" ] || { echo "Нет rosbags-convert: $CONV
Поставьте:  python3 -m venv ~/venv-rosbags && ~/venv-rosbags/bin/pip install rosbags"; exit 1; }

echo "==> конвертация $SRC -> $DST"
rm -rf "$DST"
"$CONV" --src "$SRC" --dst "$DST"

M="$DST/metadata.yaml"

# Свежий rosbags пишет offered_qos_profiles списком, Humble ждёт строку.
# Симптом без этой правки: "yaml-cpp: error at line N: bad conversion".
echo "==> metadata: offered_qos_profiles [] -> ''"
sed -i "s/offered_qos_profiles: \[\]/offered_qos_profiles: ''/g" "$M"

# Тип сообщения Livox: в ROS 1 бэгах это livox_ros_driver, у нас livox_interfaces.
# Определения идентичны, переклейка ярлыка безопасна.
echo "==> metadata: livox_ros_driver -> livox_interfaces"
sed -i 's|livox_ros_driver/msg/CustomMsg|livox_interfaces/msg/CustomMsg|g' "$M"

echo "==> проверка"
ros2 bag info "$DST"
