# Planetary Stacker - Android CMake Configuration

cmake_minimum_required(VERSION 3.10)

project(planetary_stacker VERSION 0.1.0 LANGUAGES CXX C)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Set C standard
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Compiler flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -O0")

# Source files
set(STACKER_SOURCES
    ../src/planetary_stacker.cpp
)

# Create shared library
add_library(planetary_stacker SHARED ${STACKER_SOURCES})

# Include directories
target_include_directories(planetary_stacker PRIVATE
    ../src
)

# Link libraries
# Note: Will add OpenCV and FFmpeg once configured
target_link_libraries(planetary_stacker
    android
    log
)

# Export symbols
set_target_properties(planetary_stacker PROPERTIES
    PUBLIC_HEADER ../src/planetary_stacker.h
    VERSION ${PROJECT_VERSION}
    SOVERSION 0
)

# Strip debug symbols in release builds
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    add_custom_command(TARGET planetary_stacker POST_BUILD
        COMMAND ${CMAKE_STRIP} $<TARGET_FILE:planetary_stacker>
    )
endif()
