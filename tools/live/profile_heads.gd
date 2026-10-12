extends Node
## For profile_live.gd: opens a clock at every seam of the main loop that no
## script of the game's stands at, so the bill splits what no script clocks by
## where in the loop it falls:
##   (tail)        after the meter turns the page: deferred calls, transform
##                 notifications, the nodes queued to be freed, the renderer;
##   (idle head)   coroutines resuming at the start of the idle frame;
## and a mark at the head of each physics step. Names no class of the game's.

var _ledger: Script = load("res://scripts/ledger.gd")


func _init() -> void:
	process_physics_priority = -1000000
	# After the frame meter (its ENGINE_LAST), which turns the page.
	process_priority = 1000001


func _ready() -> void:
	get_tree().physics_frame.connect(func(): _ledger.open(&"(physics head)"))
	get_tree().process_frame.connect(func(): _ledger.open(&"(idle head)"))


func _physics_process(_delta: float) -> void:
	_ledger.open(&"(physics head)")


func _process(_delta: float) -> void:
	_ledger.open(&"(tail)")
