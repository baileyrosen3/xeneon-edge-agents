import QtQuick
import QtTest
import "../components"
import "../state"
import "../state/ThemePalette.js" as ThemePalette

TestCase {
    id: tests
    name: "MonitorSettings"
    when: windowShown
    width: 2560
    height: 656
    QtObject {
        id: store
        property var omarchy: ({})
        property bool freshSnapshotRequired: false
        signal actionResultReceived(var result)
    }
    QtObject {
        id: bridge
        property bool ready: true
        property int requests: 0
        property var lastPayload: ({})
        function omarchyAction(payload) { requests += 1; lastPayload = payload; return "monitor-" + requests }
    }
    QtObject { id: activity; function noteUserActivity() {} }
    PortalStore { id: normalizer }
    Window {
        id: testWindow
        width: 2560
        height: 656
        visible: true
        MonitorSettings {
            id: panel
            anchors.fill: parent
            store: store
            bridge: bridge
            activity: activity
            theme: ThemePalette.fallback
            open: true
            reducedMotion: true
        }
    }
    function fixture() {
        return {available:true,identity_verified:true,connector:"DP-2",serial:"035926215698",model:"XENEON EDGE",edid_sha256:"5868538d290bfb3620dffaee0beb6804d0c74df803ae0bf366b9c354cf4e237b",i2c_bus:12,refreshed_at_ms:Date.now(),reason:"",display:{width:2560,height:720,refresh_hz:60.266,scale:2.5,transform:0},touch:{connected:true,device:"wch.cn-touchscreen-1"},controls:[
            {id:"brightness",label:"Brightness",kind:"continuous",supported:true,writable:true,current:95,maximum:100,choices:[]},
            {id:"backlight",label:"Backlight",kind:"continuous",supported:false,writable:false,current:null,maximum:null,choices:[],reason:"No separate DDC backlight control is exposed"},
            {id:"contrast",label:"Contrast",kind:"continuous",supported:true,writable:true,current:50,maximum:100,choices:[]},
            {id:"red_gain",label:"Red gain",kind:"continuous",supported:true,writable:true,current:151,maximum:255,choices:[]},
            {id:"green_gain",label:"Green gain",kind:"continuous",supported:true,writable:true,current:127,maximum:255,choices:[]},
            {id:"blue_gain",label:"Blue gain",kind:"continuous",supported:true,writable:true,current:139,maximum:255,choices:[]},
            {id:"sharpness",label:"Sharpness",kind:"continuous",supported:true,writable:true,current:2,maximum:4,choices:[]},
            {id:"color_preset",label:"Color preset",kind:"enum",supported:true,writable:true,current:11,maximum:null,choices:[{value:1,label:"sRGB"},{value:2,label:"Display Native"},{value:4,label:"5000 K"},{value:5,label:"6500 K"},{value:6,label:"7500 K"},{value:8,label:"9300 K"},{value:11,label:"User 1"}]}
        ]}
    }
    function init() {
        panel.finishFeedback(false, "")
        panel.needsRefresh = false
        panel.keypadControl = ""
        panel.previewMode = false
        panel.open = true
        store.freshSnapshotRequired = false
        bridge.ready = true
        bridge.requests = 0
        store.omarchy = {monitor:fixture()}
        wait(0)
    }
    function updated(id, value) {
        var next = fixture()
        next.refreshed_at_ms = store.omarchy.monitor.refreshed_at_ms + 1
        for (var i=0;i<next.controls.length;++i) if (next.controls[i].id === id) next.controls[i].current = value
        store.omarchy = {monitor:next}
    }
    function test_rawRangesUnsupportedAndPresetChoices() {
        compare(panel.control("red_gain").current,151)
        compare(panel.control("red_gain").maximum,255)
        compare(panel.control("sharpness").maximum,4)
        verify(!panel.requestSet("backlight",50))
        verify(!findChild(panel,"monitorNumeric_backlight").enabled)
        compare(panel.preset.choices.length,7)
        verify(!panel.requestSet("color_preset",3))
        verify(!panel.requestSet("red_gain",256))
        verify(!panel.requestSet("contrast",50.5))
        compare(bridge.requests,0)
    }
    function test_sliderCommitsOnlyOnReleaseAndSurvivesHealthSnapshot() {
        var slider = findChild(panel,"monitorSlider_brightness")
        var area = findChild(slider,"monitorSliderTouchArea")
        mousePress(area,area.width*.5,24)
        mouseMove(area,area.width*.7,24,20)
        compare(bridge.requests,0)
        var replacement = fixture()
        replacement.refreshed_at_ms = store.omarchy.monitor.refreshed_at_ms
        store.omarchy = {monitor:replacement}
        wait(0)
        compare(findChild(panel,"monitorSliderTouchArea") !== null,true)
        verify(slider.dragging)
        mouseRelease(area,area.width*.7,24)
        compare(bridge.requests,1)
        compare(bridge.lastPayload.operation,"monitor_set")
        compare(bridge.lastPayload.control,"brightness")
        verify(bridge.lastPayload.value>65 && bridge.lastPayload.value<75)
    }
    function test_successWaitsForFreshMatchingReadback() {
        verify(panel.requestSet("brightness",90))
        store.actionResultReceived({request_id:"monitor-1",ok:true})
        compare(panel.pendingRequest,"monitor-1")
        verify(!panel.feedbackSuccess)
        updated("brightness",90)
        compare(panel.pendingRequest,"")
        verify(panel.feedbackSuccess)
        compare(panel.control("brightness").current,90)
        compare(bridge.requests,1)
    }
    function test_readbackMayArriveBeforeResult() {
        verify(panel.requestSet("contrast",60))
        updated("contrast",60)
        compare(panel.pendingRequest,"monitor-1")
        store.actionResultReceived({request_id:"monitor-1",ok:true})
        compare(panel.pendingRequest,"")
        verify(panel.feedbackSuccess)
    }
    function test_failedWriteRequiresExplicitRefreshNeverRetries() {
        verify(panel.requestSet("brightness",90))
        store.actionResultReceived({request_id:"monitor-1",ok:false,message:"Identity no longer matches"})
        verify(panel.needsRefresh)
        verify(!panel.requestSet("brightness",80))
        compare(bridge.requests,1)
        verify(panel.refresh())
        compare(bridge.lastPayload.operation,"monitor_refresh")
        updated("brightness",95)
        store.actionResultReceived({request_id:"monitor-2",ok:true})
        verify(!panel.needsRefresh)
        compare(bridge.requests,2)
    }
    function test_timeoutRequiresExplicitRefreshWithoutResend() {
        verify(panel.requestSet("brightness",90))
        findChild(panel,"monitorWriteDeadline").triggered()
        verify(panel.needsRefresh)
        compare(panel.pendingRequest,"")
        updated("brightness",90)
        store.actionResultReceived({request_id:"monitor-1",ok:true})
        verify(panel.needsRefresh)
        verify(!panel.requestSet("brightness",80))
        compare(bridge.requests,1)
    }
    function test_previewStaleAndUnavailableNeverDispatch() {
        panel.previewMode = true
        verify(!panel.refresh())
        verify(!panel.requestSet("brightness",90))
        panel.previewMode = false
        store.freshSnapshotRequired = true
        verify(!panel.requestSet("contrast",60))
        store.freshSnapshotRequired = false
        var noIdentity=fixture();noIdentity.identity_verified=false;store.omarchy={monitor:noIdentity}
        verify(!panel.requestSet("red_gain",150))
        compare(bridge.requests,0)
    }
    function test_normalizerRejectsInvalidHardwareRanges() {
        var source=fixture();source.controls[0].maximum=100.5;source.controls[2].current=-1
        source.controls.push({id:"power",supported:true,writable:true,current:1,maximum:5})
        var result=normalizer.normalizeMonitor(source)
        compare(result.controls.length,8)
        verify(!result.controls[0].supported)
        verify(!result.controls[2].writable)
        compare(result.controls[2].current,null)
        compare(result.display.width,2560)
        compare(result.touch.connected,true)
    }
    function test_touchKeypadIntegerBounds() {
        panel.editNumber("sharpness")
        var keypad=findChild(panel,"monitorNumericPad")
        verify(keypad.integerOnly)
        keypad.accepted("5")
        compare(bridge.requests,0)
        verify(keypad.error.indexOf("4")>=0)
        keypad.accepted("3")
        compare(bridge.requests,1)
        compare(bridge.lastPayload.value,3)
    }
    function test_exportFixtureScreenshot() {
        panel.previewMode=true
        wait(40)
        var image=grabImage(testWindow.contentItem)
        image.save("/tmp/edge-monitor-settings-fixture.png")
        verify(image.width>=2560)
        compare(bridge.requests,0)
    }
}
