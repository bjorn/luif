cmake_minimum_required(VERSION 3.20)
project(luif_sdl VERSION 0.1 LANGUAGES CXX)

# The SDL3 host of Luif as a static library (luif::sdl), and luif-sdl, an
# application that runs a directory with a main.lua.
#
#   cmake -S sdl -B build && cmake --build build
#   build/luif-sdl example
#
# In another project: add_subdirectory(luif/sdl), or FetchContent with
# SOURCE_SUBDIR sdl, and link luif::sdl. SDL3::SDL3 and SDL3_ttf::SDL3_ttf
# targets that already exist are used as they are. A project with its own Lua
# defines an interface target luif_lua that links it before adding this
# directory, so that both use the same Lua.

set(LUIF_LUA "auto" CACHE STRING "Lua to build against: auto, luajit or lua")
option(LUIF_SDL_BUILD_APP "Build the luif-sdl application" ${PROJECT_IS_TOP_LEVEL})

if(NOT TARGET SDL3::SDL3)
    find_package(SDL3 3.4 REQUIRED CONFIG)
endif()
if(NOT TARGET SDL3_ttf::SDL3_ttf)
    find_package(SDL3_ttf REQUIRED CONFIG)
endif()

if(NOT TARGET luif_lua)
    add_library(luif_lua INTERFACE)
    find_package(PkgConfig QUIET)
    if(NOT LUIF_LUA STREQUAL "lua" AND PkgConfig_FOUND)
        pkg_check_modules(LUAJIT IMPORTED_TARGET luajit)
    endif()
    if(LUAJIT_FOUND)
        target_link_libraries(luif_lua INTERFACE PkgConfig::LUAJIT)
        message(STATUS "Luif: using LuaJIT ${LUAJIT_VERSION}")
    elseif(LUIF_LUA STREQUAL "luajit")
        message(FATAL_ERROR "LuaJIT not found")
    else()
        find_package(Lua 5.1 REQUIRED)
        target_include_directories(luif_lua INTERFACE ${LUA_INCLUDE_DIR})
        target_link_libraries(luif_lua INTERFACE ${LUA_LIBRARIES})
        message(STATUS "Luif: using Lua ${LUA_VERSION_STRING}")
    endif()
else()
    message(STATUS "Luif: using the Lua of the luif_lua target")
endif()

add_library(luif_sdl STATIC
    src/scene.cpp
    src/texture.cpp
    src/text.cpp
    src/render.cpp
    src/input.cpp
    src/lua_api.cpp
    src/sdl_host.cpp
)
add_library(luif::sdl ALIAS luif_sdl)
target_compile_features(luif_sdl PRIVATE cxx_std_17)
target_include_directories(luif_sdl PUBLIC include PRIVATE src)
target_link_libraries(luif_sdl PUBLIC SDL3::SDL3 luif_lua PRIVATE SDL3_ttf::SDL3_ttf)
if(NOT MSVC)
    target_compile_options(luif_sdl PRIVATE -Wall -Wextra)
endif()

if(LUIF_SDL_BUILD_APP)
    add_subdirectory(app)
endif()
