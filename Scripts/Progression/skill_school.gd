class_name SkillSchool
extends Resource
## One school of magic and its skill tree -- the horizontal axis of the system.
## Adding a school is: append one of these (with its nodes) in MockSkillTrees; the
## Skills tab's school switcher and tree view iterate whatever schools exist, so no
## UI code changes are needed to add one.

@export var id: String = ""
@export var display_name: String = "School"
@export var accent_color: Color = Color(0.6, 0.6, 0.65)
@export var nodes: Array[SkillNode] = []

func find_node(node_id: String) -> SkillNode:
	for n in nodes:
		if n.id == node_id:
			return n
	return null
