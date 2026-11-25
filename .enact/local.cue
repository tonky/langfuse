package enact

pipeline: {
	workflows: {
		local: {
			generate: false
			layout:   "staged"
			services: "on_demand"
			stages:   _stages
		}
	}
}
