	.option nopic
	.attribute arch, "rv32i2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.file	"translated_from_arm.s"
	.text
	.align	2
	.globl	main
	.type	main, %function
main:
	addi	sp,sp,-4
	sw	s0,0(sp)
	addi	s0,sp,0
	addi	sp,sp,-20
	li	a3,1
	sw	a3,-8(s0)
	li	a3,1
	sw	a3,-12(s0)
	li	a3,3
	sw	a3,-16(s0)
	j	.L2
.L3:
	lw	a2,-8(s0)
	lw	a3,-12(s0)
	add	a3,a2,a3
	sw	a3,-20(s0)
	lw	a3,-12(s0)
	sw	a3,-8(s0)
	lw	a3,-20(s0)
	sw	a3,-12(s0)
	lw	a3,-16(s0)
	addi	a3,a3,1
	sw	a3,-16(s0)
.L2:
	lw	a3,-16(s0)
	li	t4,20
	bge	t4,a3,.L3
	li	a3,0
	mv	a0,a3
	addi	sp,s0,0
	lw	s0,0(sp)
	addi	sp,sp,4
	ret
	.size	main, .-main
	.ident	"GCC: (15:9-2019-q4-0ubuntu1) 9.2.1 20191025 (release) [ARM/arm-9-branch revision 277599]"
