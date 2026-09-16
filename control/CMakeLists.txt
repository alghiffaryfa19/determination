cmake_minimum_required(VERSION 3.22)
project(aurora_control LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(auroracontrol STATIC
    src/adapter.cpp
    src/capability.cpp
    src/journal.cpp
    src/observability.cpp
    src/policy.cpp
    src/protocol.cpp
    src/sessions.cpp
    src/state.cpp
    src/system.cpp
    src/transition.cpp
)
target_include_directories(auroracontrol PUBLIC include)
target_compile_options(auroracontrol PRIVATE -Wall -Wextra -Wpedantic -Werror)

add_executable(aurorad src/aurorad.cpp)
target_link_libraries(aurorad PRIVATE auroracontrol)
target_compile_options(aurorad PRIVATE -Wall -Wextra -Wpedantic -Werror)

add_executable(auroractl src/auroractl.cpp)
target_link_libraries(auroractl PRIVATE auroracontrol)
target_compile_options(auroractl PRIVATE -Wall -Wextra -Wpedantic -Werror)

if(NOT ANDROID)
    add_executable(aurora-guest-agent src/aurora_guest_agent.cpp)
    target_link_libraries(aurora-guest-agent PRIVATE auroracontrol)
    target_compile_options(aurora-guest-agent PRIVATE
        -Wall -Wextra -Wpedantic -Werror
    )
    if(AURORA_STATIC_GUEST)
        target_link_options(aurora-guest-agent PRIVATE -static)
    endif()
endif()

if(ANDROID)
    target_link_libraries(auroracontrol PUBLIC log)
    target_link_options(aurorad PRIVATE -static-libstdc++)
    target_link_options(auroractl PRIVATE -static-libstdc++)
else()
    enable_testing()

    add_executable(aurora-control-tests
        tests/control_tests.cpp
    )
    target_link_libraries(aurora-control-tests PRIVATE auroracontrol)
    target_compile_options(aurora-control-tests PRIVATE
        -Wall -Wextra -Wpedantic -Werror
    )
    add_test(NAME aurora-control-tests COMMAND aurora-control-tests)
endif()
