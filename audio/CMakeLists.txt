cmake_minimum_required(VERSION 3.20)
project(aurora_audio LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(aurora-audio-probe src/aurora_audio_probe.cpp)
target_compile_options(aurora-audio-probe PRIVATE
    -Wall -Wextra -Wpedantic -Werror
    -ffunction-sections -fdata-sections)
target_link_options(aurora-audio-probe PRIVATE -Wl,--gc-sections)
if(AURORA_STATIC_GUEST)
    target_link_options(aurora-audio-probe PRIVATE -static)
endif()

install(TARGETS aurora-audio-probe RUNTIME DESTINATION bin)

if(ANDROID OR NOT CMAKE_CROSSCOMPILING)
    add_executable(aurora-audio-owner src/aurora_audio_owner.cpp)
    target_compile_options(aurora-audio-owner PRIVATE
        -Wall -Wextra -Wpedantic -Werror
        -ffunction-sections -fdata-sections)
    target_link_options(aurora-audio-owner PRIVATE -Wl,--gc-sections)
    install(TARGETS aurora-audio-owner RUNTIME DESTINATION bin)
endif()

include(CTest)
if(BUILD_TESTING AND NOT CMAKE_CROSSCOMPILING)
    add_test(NAME audio-probe-help COMMAND aurora-audio-probe --help)
    add_test(NAME audio-probe-fixture
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/fixture-test.sh
                $<TARGET_FILE:aurora-audio-probe>)
    add_test(NAME audio-owner-fixture
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/owner-fixture-test.sh
                $<TARGET_FILE:aurora-audio-owner>
                $<TARGET_FILE:aurora-audio-probe>)
endif()
