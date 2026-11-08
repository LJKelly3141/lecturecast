test_that("manim on PATH is used first, then uvx with the pinned version", {
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "manim") "/fake/manim" else "/fake/uvx")
  expect_equal(lc_manim_command(), "/fake/manim")
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "uvx") "/fake/uvx" else "")
  expect_equal(lc_manim_command(), c("/fake/uvx", "--from", paste0("manim==", lc_manim_version), "manim"))
  withr::local_options(lecturecast.manim_version = "0.1.0")
  expect_equal(lc_manim_command()[3], "manim==0.1.0")
})

test_that("no manim and no uv stops with a fix", {
  local_mocked_bindings(lc_find_tool = function(tool) "")
  expect_error(lc_manim_command(), "Manim was not found")
  expect_equal(lc_find_manim(), "")
})

test_that("the engine label under uvx is the pinned version, without running anything", {
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "uvx") "/fake/uvx" else "",
                        lc_run = function(...) stop("not called"))
  expect_equal(lc_manim_engine(), paste0("manim==", lc_manim_version))
})
