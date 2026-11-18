extends SceneTree
const Adapter=preload("res://scripts/ui/mobile_pose_scroll.gd")
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:push_error(label);quit(1)
func _initialize()->void:call_deferred("run")
func run()->void:
	var scroll:=ScrollContainer.new();scroll.size=Vector2(400,300);root.add_child(scroll)
	var content:=Control.new();content.custom_minimum_size=Vector2(300,3000);scroll.add_child(content)
	var adapter=Adapter.new();root.add_child(adapter);adapter.configure(scroll)
	await process_frame;await process_frame
	var bar:=scroll.get_v_scroll_bar()
	bar.value=100;check(is_equal_approx(bar.value,100),"programmatic scroll unchanged")
	adapter._mode="bar";adapter._pressed=true;adapter._origin=100;adapter._applied=100
	bar.value=200;check(is_equal_approx(bar.value,185),"thumb travel is 85 percent")
	bar.value=300;check(is_equal_approx(bar.value,270),"absolute thumb drag has no accumulated lag")
	adapter._mode="";adapter._pressed=false;bar.value=500;check(is_equal_approx(bar.value,500),"released thumb permits programmatic navigation")
	adapter._mode="touch";adapter._pressed=true;adapter._origin=500;adapter._applied=500
	bar.value=400;check(is_equal_approx(bar.value,415),"touch drag damped by 15 percent")
	adapter._pressed=false;bar.value=315;check(is_equal_approx(bar.value,330),"native inertia delta damped by 15 percent")
	adapter._mode="";bar.value=700;check(is_equal_approx(bar.value,700),"ended gesture stops damping")
	var slider:=HSlider.new();slider.min_value=-120;slider.max_value=120;slider.step=.1;slider.value=12;root.add_child(slider)
	slider.value=27.3;check(is_equal_approx(slider.value,27.3),"horizontal authored value/precision unchanged")
	check(scroll.scroll_deadzone==12,"touch deadzone explicit")
	print("POSE OPTIONS SCROLL: %d checks, 0 failures"%checks);quit()
