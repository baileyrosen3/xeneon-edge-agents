import QtQuick
import QtTest
import "../components"
import "../state/ThemePalette.js" as ThemePalette
TestCase {
    id: testCase
    name: "OmarchyHealthWarnings"
    when: windowShown
    width: 900; height: 720
    property var currentTheme: ThemePalette.fallback
    QtObject {
        id: store
        property var omarchy: ({})
        property var health: ({})
        property bool freshSnapshotRequired: false
        signal actionResultReceived(var result)
    }
    QtObject { id: bridge; property bool ready: true; function omarchyAction() { return "" } }
    QtObject { id: activity; function noteUserActivity() {} }
    Window {
        id: testWindow
        visible: true; width: 900; height: 720
        OmarchyControls {
            id: controls
            width: 900; height: 720
            store: store; bridge: bridge; activity: activity
            theme: testCase.currentTheme
        }
    }
    function test_replacedThemeAndLiveMetricsEmitNoWarning() {
        failOnWarning(/.?/)
        var cpuCard=findChild(controls,"omarchyMetric_cpu")
        var cpuLine=findChild(controls,"omarchyHistory_cpu")
        verify(cpuCard !== null)
        verify(cpuLine !== null)
        for (var i=0;i<80;++i) {
            store.health = {cpu:{available:true,value:i%100},gpu:{available:true,value:i%40},memory:{available:true,value:65}}
            currentTheme=Object.assign({},ThemePalette.fallback,{blue:i%2 ? "#FF00FF" : "#00FFFF"})
            wait(1)
            compare(findChild(controls,"omarchyMetric_cpu"),cpuCard)
            compare(String(cpuLine.lineColor).toLowerCase(),String(currentTheme.blue).toLowerCase())
        }
        compare(controls.histories.cpu.length,30)
        compare(controls.metric("cpu"),79)
        compare(controls.metricLabel("memory","%"),"65%")
    }
}
