import nimino_core

let created = newApp(id = "tech.asopi.autostart-test", name = "Autostart")
doAssert created.isOk
let app = created.value
let supported = app.supports(autostart)
doAssert supported.isOk
doAssert not supported.value
let result = app.setAutostart(true)
doAssert not result.isOk
doAssert result.failure.kind == platformUnavailable
