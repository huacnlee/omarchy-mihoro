import QtQuick
import Quickshell
import "../Model.js" as Model

// Probe: does a nested array survive the Instantiator/Repeater modelData
// boundary as a real JS Array? Reproduces the panel path
// Service.proxyGroups → Repeater → modelData.nodes → Model.sortNodesByDelay.
ShellRoot {
  Scope {
    id: probeRoot
    property var groups: [
      { name: "AI", now: "a", nodes: [ { name: "a", delay: 212 }, { name: "b", delay: 39 } ] }
    ]

    Instantiator {
      model: probeRoot.groups
      Scope {
        id: row
        required property var modelData
        Component.onCompleted: {
          var nodes = row.modelData.nodes
          console.log("typeof nodes:", typeof nodes)
          console.log("Array.isArray:", Array.isArray(nodes))
          console.log("instanceof Array:", nodes instanceof Array)
          console.log("length:", nodes && nodes.length, "nodes[0].delay:", nodes && nodes[0] ? nodes[0].delay : "?")
          var sorted = Model.sortNodesByDelay(nodes)
          console.log("sortNodesByDelay length:", sorted.length)
          Qt.quit()
        }
      }
    }
  }
}
