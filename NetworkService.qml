pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id: root
    property bool busy: agent.running
    property var prompt: null
    property string connectionName: ""
    property string error: ""
    function activate(name, kind) {
        if (busy) { OsdService.show("Connection in progress", "Finish or cancel the current network request", "network-wireless", -1, true); return; }
        connectionName=name; prompt=null; error="";
        agent.command=[Quickshell.shellPath("weylume-native"),"network-activate",name,kind]; agent.running=true;
    }
    function answer(values) { if (!prompt) return; agent.write(JSON.stringify({id:prompt.id,accept:true,values:values})+"\n"); prompt=null; }
    function cancel() { if (busy) agent.write('{"cancel":true}\n'); prompt=null; }
    Process {
        id: agent
        stdinEnabled: true
        stdout: SplitParser { onRead: line => {
            try { const m=JSON.parse(line); if(m.type==="prompt") root.prompt=m; else if(m.type==="cancel") root.prompt=null; else if(m.type==="finished") { root.error=m.ok ? "" : m.message; OsdService.show(m.ok ? "Network connected" : "Connection failed",m.message,"network-wireless",-1,!m.ok); } } catch(error) {}
        } }
        stderr: StdioCollector { onStreamFinished: if (text.trim() && !root.error) root.error=text.trim() }
        onExited: (code, status) => { root.prompt=null; if(code!==0 && root.error) OsdService.show("Connection failed",root.error,"network-wireless",-1,true); SystemService.refreshNetwork(); }
    }
    LazyLoader {
        active: root.prompt !== null
        FloatingWindow {
            visible: true; title: "Network authentication"; implicitWidth: 530; implicitHeight: 340; color: "#050505"
            onVisibleChanged: if (!visible && root.prompt !== null) root.cancel()
            Shortcut { sequence:"Escape"; onActivated:root.cancel() }
            Column {
                anchors.fill: parent; anchors.margins: 18; spacing: 8
                Text { width:parent.width; wrapMode:Text.Wrap; text:(root.prompt?.retry ? "Try again: " : "Authenticate: ") + (root.prompt?.name || root.connectionName); color:"white"; font.family:Theme.fontFamily; font.pixelSize:14 }
                Flickable {
                    width:parent.width; height:190; contentHeight:fields.implicitHeight; clip:true
                    Column {
                        id: fields; width:parent.width; spacing:6
                        Repeater { id: inputs; model:root.prompt?.fields || []; SettingsField { required property string modelData; width:fields.width; label:modelData; secret:true } }
                    }
                }
                SettingsButton { width:parent.width; label:"Use credentials for this connection"; buttonText:"Connect"; onClicked:{const values={}; for(let i=0;i<inputs.count;i++){const item=inputs.itemAt(i);values[item.modelData]=item.text;item.text="";} root.answer(values);} }
                SettingsButton { width:parent.width; label:"Cancel authentication"; buttonText:"Cancel"; onClicked:root.cancel() }
            }
        }
    }
}
