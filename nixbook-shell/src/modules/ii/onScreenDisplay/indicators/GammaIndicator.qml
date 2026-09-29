import qs.services
import QtQuick
import Quickshell
import qs.modules.ii.onScreenDisplay

OsdValueIndicator {
    id: rotateIcon

    icon: "wb_twilight"
    name: Translation.tr("Gamma")
    from: NightLightService.gammaLowerLimit / 100
    value: NightLightService.gamma / 100 ?? 0.5
}
