class_name ResourceCatalog
extends Resource

## Every commodity recognized by this game or campaign. Add new resource definition files here.
@export var resources: Array[Resource] = []


func get_resource(resource_id: StringName) -> Resource:
	for definition: Resource in resources:
		if definition != null and definition.get("resource_id") == resource_id:
			return definition
	return null


func contains(resource_id: StringName) -> bool:
	return get_resource(resource_id) != null

