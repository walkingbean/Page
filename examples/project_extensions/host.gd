extends Node
var calls := 0

func _ready() -> void:
	Dialogic.signal_event.connect(func(value): print("HOST_SIGNAL ", value))
	Dialogic.text_signal.connect(func(value): print("HOST_TEXT_SIGNAL ", value))

func record(value: String) -> void:
	calls += 1
	print("HOST_RECORD ", value, " count=", calls)

func delayed() -> void:
	print("HOST_ASYNC_BEGIN")
	await get_tree().create_timer(0.25).timeout
	print("HOST_ASYNC_END")
