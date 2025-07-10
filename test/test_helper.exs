ExUnit.start()

# Compile and load test support modules
Code.compile_file("test/support/mabeam_test_helper.ex")
Code.compile_file("test/support/agent_test_helper.ex")
Code.compile_file("test/support/system_test_helper.ex")
Code.compile_file("test/support/event_test_helper.ex")
