# TB321FU Sensor Debs

Builds the verified Qualcomm SNS sensor Debian packages for Lenovo Legion Y700 (2025) / TB321FU.

Outputs:

- qcom-sns-libssc_20260626.1_arm64.deb
- qcom-sns-hexagonrpc_20260626.1_arm64.deb
- qcom-sns-iio-sensor-proxy_20260626.1_arm64.deb
- tb321fu-sensors_20260626.1_arm64.deb
- tb321fu-sensor-debs_20260626.1_arm64.tar.gz

The source components are kept as upstream-derived branches:

- https://github.com/GUF296/libssc/tree/tb321fu-qcom-sns-20260626.1
- https://github.com/GUF296/iio-sensor-proxy/tree/tb321fu-qcom-sns-20260626.1
- https://github.com/GUF296/hexagonrpc/tree/tb321fu-qcom-sns-20260626.1

The TB321FU sensor registry/config data is stored in `device-data/hexagonfs`.
