job("Hello world") {
    git {
        // Do not download large files
        env["GIT_LFS_SKIP_SMUDGE"] = "1"
    }

    container(displayName = "Say hello", image = "hello-world")
}
