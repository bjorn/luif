# luif-sdl runs a directory with a main.lua: build/luif-sdl example
# luif-embed is a minimal game that embeds Luif and checks itself: build/luif-embed .

# The default font is compiled in, so the application is a single file.
# Bitstream Vera Sans is LOVE's built-in font too, which makes both hosts
# render alike (font/COPYRIGHT.TXT).
set(font "${CMAKE_CURRENT_SOURCE_DIR}/font/Vera.ttf")
set(embed "${CMAKE_CURRENT_SOURCE_DIR}/../cmake/embed.cmake")
set(font_cpp "${CMAKE_CURRENT_BINARY_DIR}/default_font.cpp")
add_custom_command(
    OUTPUT "${font_cpp}"
    COMMAND ${CMAKE_COMMAND} "-DINPUT=${font}" "-DOUTPUT=${font_cpp}"
            -DNAME=luif_default_font -P "${embed}"
    DEPENDS "${font}" "${embed}"
    COMMENT "Embedding Vera.ttf"
    VERBATIM
)

add_executable(luif-sdl
    main.cpp
    app_api.cpp
    "${font_cpp}"
)
target_link_libraries(luif-sdl PRIVATE luif::sdl)
set_target_properties(luif-sdl PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
if(NOT MSVC)
    target_compile_options(luif-sdl PRIVATE -Wall -Wextra)
endif()

add_executable(luif-embed embed.cpp "${font_cpp}")
target_link_libraries(luif-embed PRIVATE luif::sdl)
set_target_properties(luif-embed PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
if(NOT MSVC)
    target_compile_options(luif-embed PRIVATE -Wall -Wextra)
endif()
