extends RefCounted
## Bake-time adoption gate. Fixed uniform source-time samples are required.
## It does not assert collision feasibility; the caller must supply that verdict.
static func metrics(paths: Array) -> Dictionary:
	var step := 0.0
	var second := 0.0
	for path in paths:
		for i in range(1,path.size()): step=maxf(step,path[i].distance_to(path[i-1]))
		for i in range(2,path.size()): second=maxf(second,(path[i]-2.0*path[i-1]+path[i-2]).length())
	return {"max_step_m":step,"max_second_difference_m":second,"sample_grid":"uniform source time; displacement metrics, not physical speed or acceleration"}
static func decide(original: Dictionary, planned: Dictionary, baseline_valid: bool, route_valid: bool) -> Dictionary:
	if not route_valid: return {"apply":false,"retain_baseline":false,"status":"no_complete_model_safe_route"}
	var step_ratio: float=1.0 if float(original.max_step_m)<0.0000001 and float(planned.max_step_m)<0.0000001 else float(planned.max_step_m)/maxf(float(original.max_step_m),0.0000001)
	var second_ratio: float=1.0 if float(original.max_second_difference_m)<0.0000001 and float(planned.max_second_difference_m)<0.0000001 else float(planned.max_second_difference_m)/maxf(float(original.max_second_difference_m),0.0000001)
	var worse: bool=float(planned.max_step_m)>float(original.max_step_m)*1.01+0.000005 or float(planned.max_second_difference_m)>float(original.max_second_difference_m)*1.01+0.000005
	var meaningful: bool=step_ratio<0.95 or second_ratio<0.95
	if worse:
		return {"apply":false,"retain_baseline":baseline_valid,"status":"retain_valid_baseline" if baseline_valid else "feasible_route_failed_smoothness_gate","step_ratio":step_ratio,"second_ratio":second_ratio}
	if baseline_valid and not meaningful:
		return {"apply":false,"retain_baseline":true,"status":"retain_valid_baseline","step_ratio":step_ratio,"second_ratio":second_ratio}
	return {"apply":true,"retain_baseline":false,"status":"model_safe_and_quality_passed","step_ratio":step_ratio,"second_ratio":second_ratio}
