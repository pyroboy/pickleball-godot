extends RefCounted
## Logical cancellation only. The caller must revoke new powered-contact
## admission and retain the existing once-per-physics presentation owner.
## This never forces READY, samples a pose, changes roots, or closes passive
## finite-surface contact. Continuous recovery is a separate caller gate.
static func cancel_pending(brain,reason:String="advisory claim revoked")->Dictionary:
 if brain==null or brain._player==null:return {"cancelled":false,"reason":"missing actor"}
 var actor=brain._player
 if actor.hitting.is_in_follow_through or not actor.hitting._live_swing_presentation.is_empty():
  return {"cancelled":false,"reason":"completed contact/recovery owns presentation"}
 var before_pose=brain.incoming_pose_override
 var before_presentation=actor.posture.transition_pose_blend
 var before_root:Transform3D=actor.global_transform
 var before_paddle:Transform3D=actor.paddle_node.global_transform
 var token:int=brain._execution_commit_token
 brain.cancel_execution_commit()
 brain.ai_is_charging=false
 brain.ai_charge_time=0.0
 brain.ai_state=brain.AIState.INTERCEPT_POSITION
 brain._charge_contact_position=Vector3.ZERO
 brain._charge_target_position=Vector3.ZERO
 brain._charge_reach_pose=null
 brain._planned_shot={}
 brain._planned_flight=-1
 brain._planned_bounces=-1
 brain._planned_contact_grip=null
 brain.motion_context={}
 brain.ai_selected_contact_reachable=false
 brain.ai_selected_contact_time=-1.0
 brain.ai_reach_pose=null
 brain._movement_plan={}
 brain._movement_plan_due=0.0
 brain._contact_sweep={}
 actor.hitting.charge_visual_active=false
 return {"cancelled":true,"reason":reason,"commit_token":token,
  "presentation_unchanged":brain.incoming_pose_override==before_pose and actor.posture.transition_pose_blend==before_presentation and actor.global_transform==before_root and actor.paddle_node.global_transform==before_paddle,
  "recovery_start":before_pose,"requires_contact_claim_gate":true,"requires_continuous_recovery_owner":true}
