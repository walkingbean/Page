class_name VariableAssignment
extends RefCounted

const Literal = preload("res://application/variable_literal.gd")
const Scalar = preload("res://application/scalar_expression.gd")


static func inspect_event(source: String, values: Variant = null, evaluate: bool = true) -> Dictionary:
	var found := RegEx.create_from_string(r"\Aset[ \t]+\{(?<name>[A-Za-z_][A-Za-z0-9_]*)\}[ \t]*(?<operation>\+=|-=|\*=|/=|=)[ \t]*(?<expression>[^\r\n]+?)[ \t]*\z").search(source)
	if found == null: return {"error": "Use set {variable_name} = expression (or +=, -=, *=, /=).", "offset": 0}
	var name := found.get_string("name")
	var expression := found.get_string("expression")
	var operation: int = ["=", "+=", "-=", "*=", "/="].find(found.get_string("operation"))
	if values != null and not values.has(name): return {"error": "Assignment target '%s' is missing or has an unsupported type." % name, "offset": found.get_start("name")}
	var random := RegEx.create_from_string(r"\Arange\((-?[0-9]+),(-?[0-9]+)\)\.pick_random\(\)\z").search(expression)
	var native := DialogicVariableEvent.new()
	native.from_text(source)
	if random != null:
		var first := random.get_string(1).to_int()
		var last := random.get_string(2).to_int()
		if first < -2147483648 or last > 2147483647 or first >= last or last - first > 1000000:
			return {"error": "Random integer range requires min < max, 32-bit bounds and at most 1,000,000 values; max is exclusive.", "offset": found.get_start("expression")}
		if operation != 0 and values != null and evaluate and not (values[name] is int or values[name] is float): return {"error": "Random compound assignment requires a numeric target.", "offset": found.get_start("name")}
		if operation == DialogicVariableEvent.Operations.DIVIDE and first <= 0 and last > 0: return {"error": "A random divisor range must exclude zero.", "offset": found.get_start("expression")}
		return {"kind":"variable", "name":name, "operation":operation, "value":null, "native_value":native.value, "value_type":native._value_type, "random_min":first, "random_max":last, "runtime_unknown":true, "expression":expression}
	var direct := "set {%s} = %s" % [name, expression]
	var result := _inspect_direct(direct, values, evaluate)
	if result.has("error"):
		var old_start := direct.find(" = ") + 3
		if int(result.get("offset", 0)) >= old_start: result.offset += found.get_start("expression") - old_start
		return result
	result.operation = operation
	result.native_value = native.value
	result.value_type = native._value_type
	if native.name != name or native.operation != operation: return {"error":"The fixed native parser did not preserve this assignment.", "offset":0}
	if operation == 0 or values == null or not evaluate: return result
	var original: Variant = values[name]
	var operand: Variant = result.get("value")
	if operation == DialogicVariableEvent.Operations.ADD and original is String and native._value_type == DialogicVariableEvent.VarValueType.STRING and operand is String and not operand.is_empty():
		result.value = original + operand
		if result.value.to_utf8_buffer().size() > Scalar.MAX_VALUE_BYTES: return {"error":"Compound string exceeds the 4 MiB value limit.", "offset":found.get_start("expression")}
		return result
	if not str(original).is_valid_float() or not str(operand).is_valid_float(): return {"error":"This native compound assignment requires numeric operands.", "offset":found.get_start("expression")}
	var left := float(original)
	var right := float(operand)
	if operation == DialogicVariableEvent.Operations.DIVIDE and right == 0.0: return {"error":"Division by zero is not supported.", "offset":found.get_start("expression")}
	match operation:
		DialogicVariableEvent.Operations.ADD: result.value = left + right
		DialogicVariableEvent.Operations.SUBSTRACT: result.value = left - right
		DialogicVariableEvent.Operations.MULTIPLY: result.value = left * right
		DialogicVariableEvent.Operations.DIVIDE: result.value = left / right
	if not is_finite(float(result.value)): return {"error":"Compound result must be finite.", "offset":found.get_start("expression")}
	return result

static func _inspect_direct(source: String, values: Variant = null, evaluate: bool = true) -> Dictionary:
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
