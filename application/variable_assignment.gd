class_name VariableAssignment
extends RefCounted

const Literal = preload("res://application/variable_literal.gd")
const Scalar = preload("res://application/scalar_expression.gd")


static func inspect_event(source: String, values: Variant = null, evaluate: bool = true) -> Dictionary:
	var found := RegEx.create_from_string(r"\Aset[ \t]+\{(?<name>[A-Za-z_][A-Za-z0-9_]*)\}[ \t]*=[ \t]*(?<expression>[^\r\n]+?)[ \t]*\z").search(source)
	if found == null:
		return {"error": "Use set {variable_name} = expression. Compound assignments require a later version.", "offset": 0}
	var name := found.get_string("name")
	var expression := found.get_string("expression")
	if not Literal.parse_token(expression).has("error"):
		return Literal.inspect_event(source, values)
	if values != null and not values.has(name):
		return {"error": "Assignment target '%s' is missing or has an unsupported type." % name, "offset": found.get_start("name")}
	var result := Scalar.inspect(expression, values, evaluate)
	if result.has("error"):
		result.offset += found.get_start("expression")
		return result
	var native := DialogicVariableEvent.new()
	native.from_text(source)
	if native.name != name or native.operation != DialogicVariableEvent.Operations.SET:
		return {"error": "Native parser did not preserve the assignment target or operation.", "offset": 0}
	var actual := '"' + str(native.value) + '"' if native._value_type == DialogicVariableEvent.VarValueType.STRING else str(native.value)
	if native._value_type == DialogicVariableEvent.VarValueType.VARIABLE:
		actual = "{" + actual + "}"
	var check := Scalar.inspect(actual, values, evaluate)
	if check.has("error") or (values != null and evaluate and (typeof(check.get("value")) != typeof(result.get("value")) or check.get("value") != result.get("value"))):
		return {"error": "Alpha 20 does not preserve this expression spelling. Use explicit parentheses or encoded string quotes.", "offset": found.get_start("expression")}
	result.merge({"kind": "variable", "name": name, "native_value": native.value, "value_type": native._value_type, "expression": expression})
	return result
