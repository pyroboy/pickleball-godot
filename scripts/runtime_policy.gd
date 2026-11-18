extends RefCounted


static var mobile_runtime: bool = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or OS.get_cmdline_user_args().has("--mobile-runtime")
static var developer_tools: bool = not mobile_runtime
