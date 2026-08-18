# FAST-LIVO2 на ROS 2 Humble — Livox Avia + fisheye

Рабочая обвязка вокруг форка [Rhymer-Lcy/FAST-LIVO2-ROS2-MID360-Fisheye](https://github.com/Rhymer-Lcy/FAST-LIVO2-ROS2-MID360-Fisheye): патчи, конфиги и скрипты для запуска на **Livox Avia** (SDK1) с fisheye-камерой 150°.

Целевая платформа: Ubuntu 22.04 + ROS 2 Humble. Отладка на ноутбуке (x86_64), боевой запуск — Orange Pi 5 (RK3588S, aarch64).

---

## Почему именно этот форк

| | Rhymer-Lcy | Robotic-Developer-Road | v4rl-ucy |
|---|---|---|---|
| последний push | **2026-07** | 2025-12 | 2025-11 |
| синхронизация с hku-mars | активная | отстал | отстал |
| fisheye (Kannala-Brandt) | рабочий | конфиг не сконвертирован | взят у Rhymer-Lcy |
| параметры камеры | прямо в ноду | через `parameter_blackboard` | прямо в ноду |

`v4rl-ucy/FAST-LIVO2-ROS2` (бывший `VIS4ROB-lab`) — форк Rhymer-Lcy, отставший на восемь месяцев. Ничего уникального, кроме удобного `mapping_general.launch.py`.

---

## 1. Зависимости

```bash
sudo apt update && sudo apt install -y git python3-pip python3-venv libfmt-dev libeigen3-dev libboost-thread-dev libpcl-dev libopencv-dev ros-humble-pcl-ros ros-humble-pcl-conversions ros-humble-cv-bridge ros-humble-image-transport ros-humble-image-transport-plugins ros-humble-tf2-ros ros-humble-visualization-msgs ros-humble-demo-nodes-cpp
```

`image-transport-plugins` обязателен: без него нода `republish` падает с `Unable to load plugin for transport 'image_transport/compressed_sub'`. `demo-nodes-cpp` нужен launch-файлам, где остался `parameter_blackboard`.

### Sophus

Нужна **новая** версия (`sophus/se3.hpp`, шаблонный `SE3<double>`). В README апстрима hku-mars указан `git checkout a621ff` — это старый нешаблонный Sophus, с ним форк **не соберётся**.

```bash
git clone https://github.com/strasdat/Sophus.git -b 1.22.10 ~/Sophus && cd ~/Sophus && mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SOPHUS_TESTS=OFF -DBUILD_SOPHUS_EXAMPLES=OFF && make -j"$(nproc)" && sudo make install
```

Проверка:

```bash
ls /usr/local/include/sophus/se3.hpp
```

### rosbags (для конвертации датасетов)

Ставится в отдельный venv, чтобы не воевать с системным Python:

```bash
python3 -m venv ~/venv-rosbags && ~/venv-rosbags/bin/pip install --upgrade pip rosbags gdown
```

Бинарь не попадает в PATH — вызывать по полному пути либо повесить симлинк:

```bash
sudo ln -s ~/venv-rosbags/bin/rosbags-convert /usr/local/bin/rosbags-convert
```

---

## 2. Воркспейс

```bash
mkdir -p ~/fast_ws/src && cd ~/fast_ws/src && git clone https://github.com/Rhymer-Lcy/FAST-LIVO2-ROS2-MID360-Fisheye.git fast_livo
```

```bash
git clone https://github.com/Rhymer-Lcy/rpg_vikit_ros2_fisheye.git /tmp/vikit && cp -r /tmp/vikit/vikit_common /tmp/vikit/vikit_ros ~/fast_ws/src/
```

```bash
git clone --depth 1 https://github.com/Livox-SDK/livox_ros2_driver.git /tmp/lxd && cp -r /tmp/lxd/livox_interfaces ~/fast_ws/src/
```

**Livox-SDK2 не нужен.** Форк по умолчанию тянет `livox_ros_driver2`, который собирается поверх SDK2, а тот поддерживает только HAP и MID-360 — Avia там нет. `livox_interfaces` из `livox_ros2_driver` — самостоятельный пакет, зависит только от `std_msgs`, и определения `CustomMsg` в нём побайтово те же.

## 3. Патчи

```bash
./scripts/apply_patches.sh ~/fast_ws/src/fast_livo
```

Скрипт идемпотентен. Что делает:

1. `livox_ros_driver2` → `livox_interfaces` (13 вхождений в 6 файлах)
2. добавляет `exec_depend` в `package.xml` (в оригинале только `build_depend`)
3. глубина очередей `200000` → `10 / 2000 / 10`
4. чинит `mapping_avia_marslvig.launch.py` — он не передаёт ноде конфиг камеры
5. копирует конфиги из `configs/`

Если сборка упадёт на `CV_BGR2GRAY was not declared` — прогнать с `FIX_OPENCV=1`.

### Про глубину очередей

В ROS 1 `subscribe(topic, 200000, cb)` — потолок деки, ничего не стоит. В ROS 2 то же число становится History depth на уровне DDS. У Avia одно сообщение это 24000 точек × 20 байт ≈ **480 КБ**; при отставании подписчика история растёт до 200000 сэмплов прежде чем что-то будет отброшено. На плате с 4 ГБ это OOM вместо штатного дропа кадров.

IMU оставлен глубже (2000 ≈ 10 с при 200 Гц): один цикл LIO+VIO длиннее 50 мс, и с глубиной 10 сэмплы начали бы теряться, ломая propagation.

## 4. Сборка

```bash
cd ~/fast_ws && colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release && source install/setup.bash
```

На Orange Pi: в `CMakeLists.txt` включён `-mcpu=native`. Собирать надо **на самой плате**, либо заменить на `-mcpu=cortex-a76+crypto` — бинарники с ноутбука не поедут.

---

## 5. Датасеты

### FAST-LIVO2-Dataset

Ссылка из README апстрима (OneDrive) мертва. Живая — из [Global-LVBA](https://github.com/xuankuzcr/Global-LVBA), раздел 4: [Google Drive](https://drive.google.com/drive/folders/1bf5LQ8iSxw-fD8BObZmouw7lRxNacfrA).

```bash
~/venv-rosbags/bin/gdown 1DKOfH8pfObRenoWf4-IfkTMHcliXnigD -O ~/datasets/Retail_Street.bag
```

Доступные последовательности: `Retail_Street`, `Red_Sculpture`, `Bright_Screen_Wall`, `HKU_Landmark`, `HKU_Main_Building`, `CBD_Building_01..03`, `HIT_Graffiti_Wall_01..04`, `HKU_Centennial_Garden_01,02`, `HKU_Cultural_Center_01,02`, `HKU_Lecture_Center_01,02`, `SYSU_01,02`.

### MARS-LVIG (аэросъёмка, та же Avia)

[mars.hku.hk/dataset.html](https://mars.hku.hk/dataset.html) — серии `AMtown01..03` (посёлок, 80 м) и `AMvalley01..03` (долина, 130 м).

> **На момент написания ссылки на Google Drive отдают 404** — файлы убраны или перемещены, страница HKU не обновлена. Контакт автора: zhengcr@connect.hku.hk

Конфиги под эти серии лежат в `configs/` — в оригинале значения для AMtown/AMvalley закомментированы, активны HKisland/HKairport, и запуск «как есть» даёт молча неверную геометрию.

| серия | `img_time_offset` | `exposure_time_init` | `--start-offset` |
|---|---|---|---|
| AMtown01 | −0.1 | 0.0285 | 75 |
| AMtown02 | −0.1 | 0.0285 | 50 |
| AMtown03 | −0.1 | 0.0285 | 106 |
| AMvalley01 | −0.1 | 0.0132 | 70 |
| AMvalley02 | −0.1 | 0.0132 | 65 |
| AMvalley03 | −0.1 | 0.0132 | 68 |

В таблице внутри апстримного конфига стоит `-s` — это ROS 1. В ROS 2 `-s` означает storage id, смещение старта задаётся через `--start-offset`.

### Конвертация

```bash
./scripts/prepare_bag.sh ~/datasets/Retail_Street.bag
```

Скрипт конвертирует и чинит две вещи в `metadata.yaml`:

- `offered_qos_profiles` из пустого списка в пустую строку — свежий `rosbags` пишет список, Humble ждёт строку, иначе `yaml-cpp: error at line N: bad conversion`
- тип лидара `livox_ros_driver/msg/CustomMsg` → `livox_interfaces/msg/CustomMsg`

---

## 6. Запуск

```bash
source ~/fast_ws/install/setup.bash && ros2 launch fast_livo mapping_aviz.launch.py use_rviz:=True
```

```bash
source ~/fast_ws/install/setup.bash && ros2 bag play -p ~/datasets/Retail_Street
```

Бэг стартует на паузе, пробел — play/pause.

MARS-LVIG:

```bash
ros2 launch fast_livo mapping_avia_marslvig.launch.py use_rviz:=True avia_params_file:=$HOME/fast_ws/src/fast_livo/config/MARS_LVIG_AMtown.yaml camera_params_file:=$HOME/fast_ws/src/fast_livo/config/camera_MARS_LVIG_AM.yaml
```

```bash
ros2 bag play -p --start-offset 75 ~/datasets/AMtown01
```

### Признаки, что всё работает

```
FIRST LIDAR FRAME!
[ LIO ] Raw feature num: ... effective feature num: ...
[ VIO ] Retrieve N points from visual sparse map
[ VIO ] Append N new visual map points
```

Без rviz проверяется так:

```bash
ros2 topic hz /cloud_registered
```

```bash
ros2 topic echo /aft_mapped_to_init --once
```

---

## 7. Своё железо: Avia + fisheye

1. **Драйвер.** Avia работает через Livox-SDK1 → `livox_ros2_driver`, топик `/livox/lidar` типа `livox_interfaces/msg/CustomMsg`. Патч из п.3 уже настроил проект на этот тип.
2. **Камера.** `configs/camera_cam1_fisheye.yaml` — модель Kannala-Brandt, `EquidistantCamera`. Брать нужно ветку `fisheye` из калибровочного JSON, а не `pinhole`: rms одинаковый (0.587), но fisheye укладывается в 4 коэффициента, а `pinhole+rational` с 8 коэффициентами в vikit **не выражается** — там только 4 параметра radtan.
3. **Extrinsics** камера↔лидар — через [FAST-Calib](https://github.com/hku-mars/FAST-Calib), результат в `Rcl` / `Pcl`.

### Что важно знать про fisheye

- **Потолок 90° от оптической оси.** `world2cam` идёт через `project2d(x/z, y/z)`, `theta = atan(r)` лежит в диапазоне до π/2, плюс в коде стоят отсечки `dir[2] < 0` и `pt_c[2] > 0`. Объектив 150° (max ray 77.5°) укладывается с запасом; 190°+ давал бы выброшенное внешнее кольцо.
- **Якобиан проекции пинхольный.** `computeProjectionJacobian` в `src/vio.cpp` считает `fx/z`, то есть производную пинхольной модели, для всех типов камер. Невязка при этом точная (через настоящий `world2cam`), неверна только линеаризация. Для нашего объектива завышение: 1.8× на 40°, 4.0× на краю кадра, ~25× в углах. Фильтр недошагивает по периферийным точкам и одновременно переоценивает их информативность. **TODO:** вывести якобиан KB, примерно 20 строк.
- **Кадр не ундисторится, и это правильно** — прямой фотометрический метод работает по сырому изображению, ресемплинг размыл бы градиенты.
- **`scale` уменьшает и модель, и кадр.** `processFrame` делает `cv::resize`, если размер не совпадает с `width*scale × height*scale`. Подавать можно полный кадр, но именно номинального разрешения — промежуточные размеры ломают арифметику указателей в `getImagePatch`.

### Состояние калибровки камеры

Текущая калибровка покрывает радиус только до θ = 63.4°, тогда как углы кадра лежат на 77.5°. Верхние 16% радиуса — экстраполяция полинома, коэффициенты k3 и k4 там данными не подтверждены. **TODO:** переснять с заходом доски в углы кадра.

### Настройки под Orange Pi 5 (4 ГБ)

```yaml
publish:
  dense_map_en: false
local_map:
  map_sliding_en: true
  half_map_size: 50
pcd_save:
  pcd_save_en: false
```

---

## 8. Грабли

| Симптом | Причина и лечение |
|---|---|
| `yaml-cpp: error at line N: bad conversion` в `ros2 bag info` | `offered_qos_profiles` списком вместо строки — чинит `prepare_bag.sh` |
| `Unable to load plugin ... compressed_sub` | нет `ros-humble-image-transport-plugins` |
| `Camera model not correctly specified.` | launch не передал конфиг камеры ноде — п.3, правка 4 |
| `CV_BGR2GRAY was not declared` | константы OpenCV 3 — `FIX_OPENCV=1 ./scripts/apply_patches.sh` |
| `rosbags-convert: command not found` | стоит в venv, вызывать по полному пути |
| rviz2 падает с кодом −11, в логе `D3D12` | WSL2 — `export LIBGL_ALWAYS_SOFTWARE=1`. На нативном Linux не воспроизводится |
| `Retrieve 0 points` при ненулевом `Append` | визуальная часть не цепляется: extrinsics или `img_time_offset` |
| ROS 2 не видит топик лидара | тип в `metadata.yaml` не подменён на `livox_interfaces` |

---

## Лицензия

Исходники FAST-LIVO2 распространяются под **GPLv2**, авторы отдельно оговаривают, что коммерческое использование требует согласования с ними (zhengcr@connect.hku.hk, fuzhang@hku.hk). Этот репозиторий — производная работа и наследует те же условия.
