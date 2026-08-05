class_name Exporter
## Getting the trip back out, in formats other things already read.
##
## The logbook's own files are append-only NDJSON and will still open in a
## text editor in twenty years, but nothing else speaks them. These exports
## are what you hand to the video edit: a GPX track any mapping tool will
## draw, a Markdown journal, and a CSV of every logged moment with its
## coordinates, so a timeline in an editor can be cut against the ride.

const DIR := "user://exports"


static func export_all() -> String:
	var stamp := Time.get_datetime_string_from_unix_time(
		int(Time.get_unix_time_from_system()), false).replace(":", "").replace("-", "")
	var out := DIR.path_join("%s-%s" % [Logbook.trip_id, stamp.substr(0, 13)])
	DirAccess.make_dir_recursive_absolute(out)
	write_gpx(out.path_join("track.gpx"))
	write_journal(out.path_join("journal.md"))
	write_events_csv(out.path_join("events.csv"))
	return out


static func write_gpx(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line('<?xml version="1.0" encoding="UTF-8"?>')
	f.store_line('<gpx version="1.1" creator="Trip Logbook" xmlns="http://www.topografix.com/GPX/1/1">')
	f.store_line("  <metadata><name>%s</name></metadata>" % _xml(Logbook.trip_name()))

	# Waypoints first: every non-telemetry event becomes a pin any GPX reader
	# will show.
	for e in Logbook.events:
		if not e.has("lat") or Ev.is_minor(String(e.get("kind", ""))):
			continue
		f.store_line('  <wpt lat="%.6f" lon="%.6f">' % [float(e["lat"]), float(e["lon"])])
		f.store_line("    <time>%s</time>" % _iso(float(e.get("t", 0.0))))
		f.store_line("    <name>%s</name>" % _xml(Ev.summary(e)))
		f.store_line("    <type>%s</type>" % _xml(String(e.get("kind", ""))))
		f.store_line("  </wpt>")

	f.store_line("  <trk><name>%s</name>" % _xml(Logbook.trip_name()))
	# One <trkseg> per continuous stretch: the gaps are real and a reader
	# should not bridge them.
	var segments := Logbook.track_segments(0.0)
	var index := 0
	for seg in segments:
		var pts: PackedVector2Array = seg
		if pts.size() < 2:
			index += pts.size()
			continue
		f.store_line("    <trkseg>")
		for i in pts.size():
			var t := Logbook.times[mini(index + i, Logbook.times.size() - 1)]
			var alt := Logbook.alts[mini(index + i, Logbook.alts.size() - 1)]
			f.store_line('      <trkpt lat="%.6f" lon="%.6f"><ele>%.1f</ele><time>%s</time></trkpt>'
				% [pts[i].x, pts[i].y, alt, _iso(t)])
		f.store_line("    </trkseg>")
		index += pts.size()
	f.store_line("  </trk>")
	f.store_line("</gpx>")


static func write_journal(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("# %s" % Logbook.trip_name())
	f.store_line("")
	f.store_line("%s · %s ridden · %d days" % [UI.date_line(Logbook.start_time()),
		Cfg.dist(Logbook.total_m), maxi(1, Logbook.days().size())])
	f.store_line("")
	var days := Logbook.days()
	for i in days.size():
		var d: Dictionary = days[i]
		f.store_line("## Day %d — %s" % [i + 1, UI.date_line(float(d["t0"]))])
		f.store_line("")
		f.store_line("%s ridden, %s moving, %s climbed."
			% [Cfg.dist(float(d["meters"])), Trip.format_duration(float(d["moving"])),
			Cfg.elev(float(d["climb"]))])
		# The energy ledger for the day, if the rig was reporting.
		for e in Logbook.events_between(float(d["t0"]), float(d["t1"]), [Ev.DAY_END]):
			if not e.has("wh_used"):
				continue
			f.store_line("")
			f.store_line("Energy: %d Wh used · %d Wh solar · %d Wh regen."
				% [int(e.get("wh_used", 0.0)), int(e.get("wh_solar", 0.0)),
				int(e.get("wh_regen", 0.0))])
		f.store_line("")
		for e in Logbook.events_between(float(d["t0"]), float(d["t1"])):
			var kind := String(e.get("kind", ""))
			if Ev.is_minor(kind):
				continue
			var where := ""
			if e.has("lat"):
				where = "  _(%s)_" % Geo.format_latlon(float(e["lat"]), float(e["lon"]))
			if kind == Ev.NOTE:
				f.store_line("**%s**%s" % [UI.clock(float(e.get("t", 0.0))), where])
				f.store_line("")
				f.store_line(String(e.get("text", "")))
				f.store_line("")
			else:
				f.store_line("- `%s` %s — %s%s" % [UI.clock(float(e.get("t", 0.0))),
					Ev.glyph(kind), Ev.summary(e), where])
		f.store_line("")


static func write_events_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("iso_time,unix,kind,lat,lon,summary")
	for e in Logbook.events:
		var t := float(e.get("t", 0.0))
		f.store_line('%s,%d,%s,%s,%s,"%s"' % [
			_iso(t), int(t), String(e.get("kind", "")),
			("%.6f" % float(e["lat"])) if e.has("lat") else "",
			("%.6f" % float(e["lon"])) if e.has("lon") else "",
			Ev.summary(e).replace('"', "'"),
		])


static func _iso(t: float) -> String:
	return Time.get_datetime_string_from_unix_time(int(t), true) + "Z"


static func _xml(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
