# Script mode helper for mcu_fetch_package(SPARSE_PATHS ...):
#   cmake -DREPOSITORY=<url> -DREF=<tag|commit> -DPATHS=<a,b,c> -DDIR=<dir>
#         -DGIT=<git executable> -P git_sparse_fetch.cmake
#
# Fetches only <ref> (depth 1) as a partial clone (--filter=blob:none) with a
# cone-mode sparse checkout of PATHS, so only the files under those
# directories (plus top-level files) are downloaded. Skips the work when DIR
# already holds the same repository, ref and paths.

foreach(var REPOSITORY REF PATHS DIR GIT)
  if(NOT DEFINED ${var} OR "${${var}}" STREQUAL "")
    message(FATAL_ERROR "git_sparse_fetch: ${var} is required")
  endif()
endforeach()
string(REPLACE "," ";" paths "${PATHS}")

set(stamp_file "${DIR}/.mcu-sparse-fetch")
set(stamp "${REPOSITORY}\n${REF}\n${PATHS}\n")
if(EXISTS "${stamp_file}")
  file(READ "${stamp_file}" previous)
  if(previous STREQUAL stamp)
    return()
  endif()
endif()

file(REMOVE_RECURSE "${DIR}")
file(MAKE_DIRECTORY "${DIR}")

function(_git)
  execute_process(
    COMMAND "${GIT}" ${ARGN}
    WORKING_DIRECTORY "${DIR}"
    RESULT_VARIABLE result
    ERROR_VARIABLE error
    OUTPUT_QUIET
  )
  if(NOT result EQUAL 0)
    string(REPLACE ";" " " command "${ARGN}")
    message(FATAL_ERROR "git_sparse_fetch: 'git ${command}' failed:\n${error}")
  endif()
endfunction()

_git(init -q)
_git(remote add origin "${REPOSITORY}")
_git(sparse-checkout set --cone ${paths})
# Fetching a tag name or a full commit hash both work with depth 1 on hosts
# that allow fetching reachable commits by hash (GitHub, GitLab).
_git(fetch -q --depth 1 --filter=blob:none origin "${REF}")
_git(checkout -q FETCH_HEAD)

file(WRITE "${stamp_file}" "${stamp}")
