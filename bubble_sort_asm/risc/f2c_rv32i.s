	.file	"f2c.c"
	.option nopic
	.attribute arch, "rv32i2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.globl	__divsi3
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32
	sw	ra,28(sp)
	sw	s0,24(sp)
	addi	s0,sp,32
	li	a5,25
	sw	a5,-20(s0)
	lw	a4,-20(s0)
	mv	a5,a4
	slli	a5,a5,3
	add	a5,a5,a4
	li	a1,5
	mv	a0,a5
	call	__divsi3
	mv	a5,a0
	addi	a5,a5,32
	sw	a5,-24(s0)
	li	a5,0
	mv	a0,a5
	lw	ra,28(sp)
	lw	s0,24(sp)
	addi	sp,sp,32
	jr	ra
	.size	main, .-main
	.ident	"GCC: () 9.3.0"
