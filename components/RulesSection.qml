import QtQuick
import qs.Commons
import qs.Ui
import "../Rules.js" as Rules

Column {
  id: root

  required property var service
  required property color textColor
  required property string panelFontFamily
  property string subscriptionId: ""
  property var draftRules: []
  property bool dirty: false
  property bool editing: false
  property bool applyPending: false
  property string editingId: ""
  property string confirmingId: ""

  signal backRequested()
  signal applyRequested(string subscriptionId, var rules)

  spacing: Style.space(8)

  readonly property var typeOptions: [
    { value: "DOMAIN", label: "Domain" },
    { value: "DOMAIN-SUFFIX", label: "Domain suffix" },
    { value: "DOMAIN-KEYWORD", label: "Domain keyword" },
    { value: "GEOSITE", label: "GeoSite" }
  ]
  readonly property var geoSiteOptions: ["CN", "private", "geolocation-!cn"]
  readonly property string editorError: Rules.ruleError(typeField.value,
    typeField.value === "GEOSITE" ? geoSiteField.value : matchField.text, routeField.value)

  Connections {
    target: root.service
    function onRulesApplyFinished(ok) {
      if (!root.applyPending) return
      root.applyPending = false
      if (ok) {
        root.draftRules = root.service.rulesFor(root.subscriptionId)
        root.dirty = false
      }
    }
  }

  function begin(id) {
    var wanted = String(id || "")
    root.subscriptionId = wanted
    root.draftRules = root.service.rulesFor(wanted)
    root.dirty = false
    root.editing = false
    root.editingId = ""
    root.confirmingId = ""
  }

  function beginAdd() {
    root.editingId = ""
    typeField.value = "DOMAIN-SUFFIX"
    matchField.text = ""
    geoSiteField.value = "CN"
    routeField.value = "DIRECT"
    root.editing = true
  }

  function beginEdit(rule) {
    root.editingId = String(rule.id)
    typeField.value = String(rule.type)
    matchField.text = String(rule.match)
    geoSiteField.value = String(rule.match)
    routeField.value = String(rule.route)
    root.editing = true
  }

  function saveEdit() {
    if (root.editorError !== "") return
    var next = root.draftRules.slice()
    var match = typeField.value === "GEOSITE" ? geoSiteField.value : matchField.text.trim()
    if (root.editingId === "") {
      next.push({ id: Date.now().toString(36) + "-" + Math.random().toString(36).substring(2, 9),
        type: typeField.value, match: match, route: routeField.value })
    } else {
      for (var i = 0; i < next.length; i++) {
        if (String(next[i].id) !== root.editingId) continue
        next[i] = { id: root.editingId, type: typeField.value, match: match, route: routeField.value }
      }
    }
    root.draftRules = next
    root.dirty = true
    root.editing = false
    root.editingId = ""
  }

  function moveRule(index, delta) {
    var to = Math.max(0, Math.min(root.draftRules.length - 1, index + delta))
    if (to === index) return
    var next = root.draftRules.slice()
    var item = next.splice(index, 1)[0]
    next.splice(to, 0, item)
    root.draftRules = next
    root.dirty = true
  }

  function remove(id) {
    var next = []
    for (var i = 0; i < root.draftRules.length; i++)
      if (String(root.draftRules[i].id) !== String(id)) next.push(root.draftRules[i])
    root.draftRules = next
    root.confirmingId = ""
    root.dirty = true
  }

  Item {
    width: parent.width
    implicitHeight: rulesHeader.implicitHeight
    Row {
      id: rulesHeader
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
      Button {
        text: "←"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.title
        onClicked: {
          if (root.editing) root.editing = false
          else root.backRequested()
        }
      }
      PanelSectionHeader {
        anchors.verticalCenter: parent.verticalCenter
        text: root.editing ? (root.editingId === "" ? "ADD RULE" : "EDIT RULE") : "LOCAL RULES"
        foreground: root.textColor
        fontFamily: root.panelFontFamily
      }
    }
  }

  Column {
    visible: !root.editing
    width: parent.width
    spacing: Style.space(6)

    Text {
      visible: root.draftRules.length === 0
      width: parent.width
      text: "No local rules. Subscription rules are used unchanged."
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.58)
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: root.draftRules
      delegate: Rectangle {
        id: ruleRow
        required property int index
        required property var modelData
        width: root.width
        implicitHeight: Style.space(52)
        radius: Style.cornerRadius
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.04)
        border.width: 1
        border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: ruleActions.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: (ruleRow.index + 1) + "  " + String(ruleRow.modelData.type)
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: String(ruleRow.modelData.match) + "  →  " + String(ruleRow.modelData.route)
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        Row {
          id: ruleActions
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)
          visible: root.confirmingId !== String(ruleRow.modelData.id)
          Repeater {
            model: [
              { icon: "arrow-up", label: "Move rule up", enabled: ruleRow.index > 0, action: -1 },
              { icon: "arrow-down", label: "Move rule down", enabled: ruleRow.index < root.draftRules.length - 1, action: 1 }
            ]
            delegate: PanelActionButton {
              required property var modelData
              tooltipText: modelData.label
              foreground: root.textColor
              hoverColor: root.textColor
              fontFamily: root.panelFontFamily
              enabled: modelData.enabled
              onClicked: root.moveRule(ruleRow.index, modelData.action)
              ActionIcon { anchors.centerIn: parent; name: modelData.icon; iconSize: Style.font.icon; color: root.textColor }
            }
          }
          PanelActionButton {
            tooltipText: "Edit rule..."
            foreground: root.textColor
            hoverColor: root.textColor
            fontFamily: root.panelFontFamily
            onClicked: root.beginEdit(ruleRow.modelData)
            ActionIcon { anchors.centerIn: parent; name: "edit"; iconSize: Style.font.icon; color: root.textColor }
          }
          PanelActionButton {
            tooltipText: "Remove rule"
            foreground: root.textColor
            hoverColor: Color.urgent
            fontFamily: root.panelFontFamily
            onClicked: root.confirmingId = String(ruleRow.modelData.id)
            ActionIcon { anchors.centerIn: parent; name: "trash"; iconSize: Style.font.icon; color: Color.urgent }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: root.confirmingId === String(ruleRow.modelData.id)
          spacing: Style.space(3)
          Button { text: "Remove"; foreground: Color.urgent; bordered: true; fontSize: Style.font.caption; onClicked: root.remove(ruleRow.modelData.id) }
          Button { text: "Cancel"; foreground: root.textColor; bordered: true; fontSize: Style.font.caption; onClicked: root.confirmingId = "" }
        }
      }
    }

    Button {
      width: parent.width
      text: "Add rule..."
      foreground: root.textColor
      bordered: true
      enabled: !root.service.rulesApplying
      fontSize: Style.font.bodySmall
      onClicked: root.beginAdd()
    }

    Button {
      width: parent.width
      text: root.service.rulesApplying ? "Applying…" : "Apply"
      foreground: root.textColor
      bordered: true
      enabled: root.dirty && !root.service.rulesApplying
      fontSize: Style.font.bodySmall
      onClicked: {
        root.applyPending = true
        root.applyRequested(root.subscriptionId, root.draftRules)
      }
    }
  }

  Column {
    visible: root.editing
    width: parent.width
    spacing: Style.space(8)
    Dropdown {
      id: typeField
      width: parent.width
      label: "TYPE"
      value: "DOMAIN-SUFFIX"
      options: root.typeOptions
      foreground: root.textColor
      fontFamily: root.panelFontFamily
      onChanged: function(value) { typeField.value = value; if (value === "GEOSITE" && geoSiteField.value === "") geoSiteField.value = "CN" }
    }
    TextField {
      id: matchField
      visible: typeField.value !== "GEOSITE"
      width: parent.width
      foreground: root.textColor
      accent: Color.accent
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.body
      placeholderText: typeField.value === "DOMAIN-KEYWORD" ? "google" : "example.com"
    }
    Dropdown {
      id: geoSiteField
      visible: typeField.value === "GEOSITE"
      width: parent.width
      label: "MATCH"
      value: "CN"
      options: root.geoSiteOptions
      foreground: root.textColor
      fontFamily: root.panelFontFamily
      onChanged: function(value) { geoSiteField.value = value }
    }
    Dropdown {
      id: routeField
      width: parent.width
      label: "ROUTE"
      value: "DIRECT"
      options: root.service.routeOptions
      foreground: root.textColor
      fontFamily: root.panelFontFamily
      onChanged: function(value) { routeField.value = value }
    }
    Text {
      visible: root.editorError !== ""
      width: parent.width
      text: root.editorError
      color: Color.urgent
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }
    Row {
      width: parent.width
      spacing: Style.spacing.controlGap
      Button { width: (parent.width - parent.spacing) / 2; text: "Save"; foreground: root.textColor; bordered: true; enabled: root.editorError === ""; fontSize: Style.font.bodySmall; onClicked: root.saveEdit() }
      Button { width: (parent.width - parent.spacing) / 2; text: "Cancel"; foreground: root.textColor; bordered: true; fontSize: Style.font.bodySmall; onClicked: root.editing = false }
    }
  }
}
