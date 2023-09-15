struct stat {
	dev_t st_dev;
	int __pad1[3];
	ino_t st_ino;
	mode_t st_mode;
	nlink_t st_nlink;
	uid_t st_uid;
	gid_t st_gid;
	dev_t st_rdev;
	unsigned int __pad2[2];
	off_t st_size;
	int __pad3;
	struct timespec st_atim;
	struct timespec st_mtim;
	struct timespec st_ctim;
	blksize_t st_blksize;
	unsigned int __pad4;
	blkcnt_t st_blocks;
	int __pad5[14];
};