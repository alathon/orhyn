class_name WizardAnimationTree
extends ModelAnimationTree


func _get_actions() -> Dictionary:
	return {
		ModelAnimationActions.LIFECYCLE_DEATH: _validation_clip(&"Death"),
		ModelAnimationActions.LOCOMOTION_IDLE: _validation_clip(&"Idle"),
		ModelAnimationActions.LOCOMOTION_WALK: _validation_clip(&"Walk"),
		ModelAnimationActions.LOCOMOTION_RUN: _validation_clip(&"Run"),
		ModelAnimationActions.LOCOMOTION_JUMP: _validation_clip(&"Roll"),
		ModelAnimationActions.START_CASTING: _action(&"Spell2", "parameters/CastStartOneShot/request", "parameters/CastStartTimeScale/scale"),
		ModelAnimationActions.FINISH_CASTING: _action(&"Spell1", "parameters/CastFinishOneShot/request", "parameters/CastFinishTimeScale/scale"),
		ModelAnimationActions.MELEE_ATTACK: _direct_action(&"Staff_Attack"),
		ModelAnimationActions.TAKE_HIT: _direct_action(&"RecieveHit"),
	}
