extends RefCounted

# Godot 4.7.1 PackedSourcePCK and PC exporters: relative PCK offsets,
# executable pck section, then uint64 pack size + GDPC footer.
# Only the resource section metadata changes; the running engine is reused.
const MAGIC := 0x43504447
const CHUNK := 1024 * 1024

static func embed(executable: String, pack: String, destination: String) -> String:
	if FileAccess.file_exists(destination): return "Preview executable already exists."
	var source := FileAccess.open(executable, FileAccess.READ)
	var payload := FileAccess.open(pack, FileAccess.READ)
	if source == null or payload == null: return "Cannot read the engine or target pack."
	if source.get_length() < 64 or payload.get_length() < 100: return "Truncated engine or target pack."
	source.seek(source.get_length() - 12)
	var previous_size := source.get_64()
	if source.get_32() != MAGIC or previous_size <= 0 or previous_size > source.get_length() - 64: return "The PAGE executable has no supported embedded pack."
	var start := source.get_length() - 12 - previous_size
	source.seek(start)
	if source.get_32() != MAGIC: return "Invalid embedded pack boundary."
	if payload.get_32() != MAGIC or payload.get_32() not in [3, 4]: return "Unsupported preview pack format."
	var section := _section(source, start)
	if section.has("error"): return section.error
	var new_size := payload.get_length() + 12
	if section.format == "pe" and start + new_size >= 0x100000000: return "Windows preview executable must be smaller than 4 GiB."
	var output := FileAccess.open(destination, FileAccess.WRITE_READ)
	if output == null: return "Cannot create the independent preview executable."
	source.seek(0); payload.seek(0)
	var valid := _copy(source, output, start) and _copy(payload, output, payload.get_length())
	output.store_64(payload.get_length()); output.store_32(MAGIC)
	output.seek(section.offset)
	if section.format == "elf": output.store_64(new_size)
	else: output.store_32(new_size)
	output.flush()
	valid = valid and output.get_error() == OK and output.get_length() == start + new_size
	output.close(); source.close(); payload.close()
	if not valid:
		DirAccess.remove_absolute(destination)
		return "Writing the independent preview executable failed."
	if OS.get_name() != "Windows" and FileAccess.set_unix_permissions(destination, 448) != OK:
		DirAccess.remove_absolute(destination)
		return "Cannot grant execute permission to the target preview."
	return ""

static func _copy(source: FileAccess, output: FileAccess, remaining: int) -> bool:
	while remaining > 0:
		var count := mini(CHUNK, remaining)
		var bytes := source.get_buffer(count)
		if bytes.size() != count: return false
		output.store_buffer(bytes)
		if output.get_error() != OK: return false
		remaining -= count
	return true

static func _section(file: FileAccess, pack_start: int) -> Dictionary:
	file.seek(0)
	var magic := file.get_32()
	if magic == 0x464c457f:
		if file.get_8() != 2 or file.get_8() != 1: return {"error":"Preview requires a little-endian 64-bit ELF executable."}
		file.seek(0x28); var table := file.get_64()
		file.seek(0x3a); var stride := file.get_16(); var count := file.get_16(); var strings_index := file.get_16()
		if stride != 64 or table + count * stride > pack_start or strings_index >= count: return {"error":"Invalid ELF section table."}
		file.seek(table + strings_index * stride + 0x18)
		var strings_start := file.get_64(); var strings_size := file.get_64()
		if strings_start + strings_size > pack_start or strings_size > CHUNK: return {"error":"Invalid ELF section names."}
		file.seek(strings_start); var names := file.get_buffer(strings_size)
		for i: int in count:
			var header := table + i * stride
			file.seek(header); var name := file.get_32()
			if name + 4 <= names.size() and names.slice(name, name + 4) == PackedByteArray([112, 99, 107, 0]):
				file.seek(header + 0x18)
				if file.get_64() != pack_start: return {"error":"ELF pack offset does not match its footer."}
				return {"format":"elf", "offset":header + 0x20}
	elif magic & 0xffff == 0x5a4d:
		file.seek(0x3c); var pe := file.get_32()
		if pe + 24 > pack_start: return {"error":"Invalid PE header."}
		file.seek(pe)
		if file.get_32() != 0x4550: return {"error":"Invalid PE signature."}
		if file.get_16() != 0x8664: return {"error":"Preview requires an x86-64 Windows executable."}
		var count := file.get_16()
		file.seek(pe + 20); var optional_size := file.get_16()
		var table := pe + 24 + optional_size
		if table + count * 40 > pack_start: return {"error":"Invalid PE section table."}
		for i: int in count:
			var header := table + i * 40
			file.seek(header)
			if file.get_buffer(8) == PackedByteArray([112, 99, 107, 0, 0, 0, 0, 0]):
				file.seek(header + 20)
				if file.get_32() != pack_start: return {"error":"PE pack offset does not match its footer."}
				return {"format":"pe", "offset":header + 16}
	return {"error":"The executable has no supported native pck section."}
