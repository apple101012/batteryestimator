set pluginDir to (POSIX path of (path to home folder)) & "Documents/Github/batteryestimator"
set pluginFile to pluginDir & "battery-estimate.1m.sh"
set swiftBarAppPath to "/Applications/SwiftBar.app"

try
	do shell script "test -d " & quoted form of pluginDir
on error
	display dialog "Battery estimator folder is missing: " & pluginDir buttons {"OK"} default button "OK" with icon caution
	return
end try

try
	do shell script "test -x " & quoted form of pluginFile
on error
	display dialog "Battery plugin is missing or not executable: " & pluginFile buttons {"OK"} default button "OK" with icon caution
	return
end try

try
	do shell script "test -d " & quoted form of swiftBarAppPath
on error
	display dialog "SwiftBar is not installed in /Applications." buttons {"OK"} default button "OK" with icon caution
	return
end try

do shell script "defaults write com.ameba.SwiftBar PluginDirectory -string " & quoted form of pluginDir
do shell script "defaults write com.ameba.SwiftBar pluginDirectoryPath -string " & quoted form of pluginDir
do shell script "defaults write com.ameba.SwiftBar swiftBarIconIsHidden -bool YES"
do shell script "killall SwiftBar >/dev/null 2>&1 || true"

tell application "SwiftBar" to launch
delay 1

display notification "Battery estimator is running through SwiftBar." with title "Battery Usage"
