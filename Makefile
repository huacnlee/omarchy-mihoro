QMLLINT := /usr/lib/qt6/bin/qmllint
QML_FILES := Panel.qml Service.qml \
	components/MihoroIcon.qml \
	components/SettingsIcon.qml \
	components/SystemTheme.qml \
	components/StatRow.qml \
	components/ModeSection.qml \
	components/ConnectionSection.qml \
	components/SubscriptionSection.qml \
	components/InstallSection.qml \
	components/SetupCard.qml \
	components/PanelMenu.qml

.PHONY: test test-js test-shell qml-check validate

test: test-js test-shell

# The parsing, formatting, and command-building live in plain JS precisely so
# they can be tested without a compositor. These run anywhere node does.
test-js:
	node tests/test_theme_colors.js
	node tests/test_mihoro_config.js
	node tests/test_clash_api.js
	node tests/test_model.js

test-shell:
	python3 tests/test_qml_names.py
	bash tests/test_install.sh
	bash tests/test_panel_source.sh

# Needs the Omarchy shell's qs.Commons / qs.Ui on the import path.
qml-check:
	$(QMLLINT) -I /usr/share/omarchy/shell $(QML_FILES)

validate: test qml-check
	omarchy plugin validate .
	git diff --check
