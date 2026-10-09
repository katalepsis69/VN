extends Node

## GitHub Releases Updater for ADHD VN Reader
## Checks katalepsis69/VN for new releases and handles in-app updates.

signal check_completed(has_update: bool, latest_ver: String, notes: String, download_url: String, html_url: String)
signal download_progress(downloaded: int, total: int, percent: int)
signal download_finished(success: bool, error_msg: String)

const REPO := "katalepsis69/VN"
const CURRENT_VERSION := "1.0"

var _check_http: HTTPRequest
var _download_http: HTTPRequest
var _is_checking: bool = false
var _is_downloading: bool = false

var _latest_version: String = ""
var _download_url: String = ""
var _html_url: String = ""
var _release_notes: String = ""
var _expected_bytes: int = 0

func _ready() -> void:
	_check_http = HTTPRequest.new()
	_check_http.timeout = 10.0
	_check_http.request_completed.connect(_on_check_completed)
	add_child(_check_http)

	_download_http = HTTPRequest.new()
	_download_http.timeout = 0.0 # No timeout for streaming large download
	_download_http.request_completed.connect(_on_download_completed)
	add_child(_download_http)

## Parse 2-digit version string (e.g. "v1.1", "1.2", "v2.0") into [major, minor]
static func parse_version_parts(v: String) -> Array[int]:
	var clean := v.strip_edges().trim_prefix("v").trim_prefix("V")
	if "+" in clean:
		clean = clean.split("+")[0]
	var parts := clean.split(".")
	var major := int(parts[0]) if parts.size() > 0 and parts[0].is_valid_int() else 0
	var minor := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 0
	return [major, minor]

## Compares remote version with local version using 2-digit semver (major.minor)
static func is_remote_newer(remote_v: String, local_v: String) -> bool:
	var r := parse_version_parts(remote_v)
	var l := parse_version_parts(local_v)
	if r[0] > l[0]:
		return true
	if r[0] == l[0] and r[1] > l[1]:
		return true
	return false

## Start background check against GitHub Releases API
func check_for_updates() -> void:
	if _is_checking:
		return
	_is_checking = true
	var url := "https://api.github.com/repos/%s/releases/latest" % REPO
	var headers := PackedStringArray([
		"User-Agent: VNReader-Updater",
		"Accept: application/vnd.github+json"
	])
	var err := _check_http.request(url, headers)
	if err != OK:
		_is_checking = false
		check_completed.emit(false, "", "", "", "")

func _on_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_checking = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		check_completed.emit(false, "", "", "", "")
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		check_completed.emit(false, "", "", "", "")
		return

	var data: Dictionary = json.data
	var tag: String = str(data.get("tag_name", "")).strip_edges()
	if tag.is_empty():
		check_completed.emit(false, "", "", "", "")
		return

	_latest_version = tag
	_html_url = str(data.get("html_url", ""))
	_release_notes = str(data.get("body", ""))

	# Locate executable asset (VNReader.exe)
	_download_url = ""
	_expected_bytes = 0
	var assets: Variant = data.get("assets", [])
	if assets is Array:
		for a in assets:
			if a is Dictionary and str(a.get("name", "")).to_lower() == "vnreader.exe":
				_download_url = str(a.get("browser_download_url", ""))
				_expected_bytes = int(a.get("size", 0))
				break
		if _download_url.is_empty():
			for a in assets:
				if a is Dictionary and str(a.get("name", "")).to_lower().ends_with(".exe"):
					_download_url = str(a.get("browser_download_url", ""))
					_expected_bytes = int(a.get("size", 0))
					break

	var newer := is_remote_newer(_latest_version, CURRENT_VERSION)
	check_completed.emit(newer, _latest_version, _release_notes, _download_url, _html_url)

## Download the update and launch the Windows helper script to replace the running exe
func start_download_and_apply(target_url: String = "") -> void:
	if _is_downloading:
		return
	var dl_url := target_url if not target_url.is_empty() else _download_url

	# In editor, never overwrite the Godot executable; open release in browser instead
	if OS.has_feature("editor"):
		var web_url := _html_url if not _html_url.is_empty() else "https://github.com/%s/releases" % REPO
		OS.shell_open(web_url)
		download_finished.emit(false, "Running in editor: opened download page in browser.")
		return

	if dl_url.is_empty():
		if not _html_url.is_empty():
			OS.shell_open(_html_url)
		download_finished.emit(false, "No executable download link available. Opened release page.")
		return

	_is_downloading = true
	var staging_path := "user://VNReader_update.exe"
	_download_http.download_file = staging_path

	var headers := PackedStringArray([
		"User-Agent: VNReader-Updater",
		"Accept: application/octet-stream"
	])
	var err := _download_http.request(dl_url, headers)
	if err != OK:
		_is_downloading = false
		download_finished.emit(false, "Could not start download (error %d)." % err)

func _process(_delta: float) -> void:
	if not _is_downloading or _download_http == null:
		return
	var downloaded := _download_http.get_downloaded_bytes()
	var total := _download_http.get_body_size()
	if total <= 0:
		total = _expected_bytes
	var percent := 0
	if total > 0:
		percent = clampi(int((float(downloaded) / float(total)) * 100.0), 0, 100)
	download_progress.emit(downloaded, total, percent)

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_is_downloading = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		download_finished.emit(false, "Download failed with HTTP code %d." % response_code)
		return

	var staging_vpath := "user://VNReader_update.exe"
	if not FileAccess.file_exists(staging_vpath):
		download_finished.emit(false, "Downloaded file not found on disk.")
		return

	var f := FileAccess.open(staging_vpath, FileAccess.READ)
	if f == null or f.get_length() < 1024 * 1024:
		download_finished.emit(false, "Downloaded update is incomplete or corrupt.")
		return
	f.close()

	_apply_and_restart()

func _apply_and_restart() -> void:
	var staging_abs := ProjectSettings.globalize_path("user://VNReader_update.exe")
	var current_exe := OS.get_executable_path()
	var current_pid := OS.get_process_id()
	var script_path := ProjectSettings.globalize_path("user://apply_update.cmd")

	var win_staging := staging_abs.replace("/", "\\")
	var win_exe := current_exe.replace("/", "\\")
	var win_script := script_path.replace("/", "\\")

	var cmd_content := "@echo off\r\n"
	cmd_content += ":wait\r\n"
	cmd_content += 'tasklist /fi "PID eq %d" | findstr "%d" >nul\r\n' % [current_pid, current_pid]
	cmd_content += "if not errorlevel 1 (timeout /t 1 /nobreak >nul & goto wait)\r\n"
	cmd_content += "timeout /t 1 /nobreak >nul\r\n"
	cmd_content += ":copyloop\r\n"
	cmd_content += 'copy /y "%s" "%s" >nul\r\n' % [win_staging, win_exe]
	cmd_content += "if errorlevel 1 (\r\n"
	cmd_content += "    timeout /t 1 /nobreak >nul\r\n"
	cmd_content += "    goto copyloop\r\n"
	cmd_content += ")\r\n"
	cmd_content += 'powershell -NoProfile -Command "Unblock-File \'%s\'" >nul 2>&1\r\n' % win_exe
	cmd_content += 'start "" "%s"\r\n' % win_exe
	cmd_content += '(goto) 2>nul & del "%~f0"\r\n'

	var out_f := FileAccess.open("user://apply_update.cmd", FileAccess.WRITE)
	if out_f == null:
		download_finished.emit(false, "Could not write update script.")
		return
	out_f.store_string(cmd_content)
	out_f.close()

	OS.create_process("cmd.exe", ["/c", win_script], false)
	get_tree().quit()
