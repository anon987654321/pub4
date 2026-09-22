import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import { bootPub4Stimulus } from "pub4/stimulus_boot"
import { bootSocialStimulus } from "pub4/stimulus_boot_social"
import { bootBrgenStimulus } from "pub4/stimulus_boot_brgen"

bootPub4Stimulus(application)
bootSocialStimulus(application)
bootBrgenStimulus(application)
eagerLoadControllersFrom("controllers", application)
