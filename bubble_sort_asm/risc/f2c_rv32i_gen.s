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
	addi	sp,sp,-12
	li	a3,25
	sw	a3,-8(s0)
	lw	a2,-8(s0)
	mv	a3,a2
	slli	a3,a3,3
	add	a3,a3,a2
	li	a2,1717986919
	mul	a1,a3,a2
	mulh	a2,a3,a2
	srai	a2,a2,1
	srai	a3,a3,31
	sub	a3,a2,a3
	addi	a3,a3,32
	sw	a3,-12(s0)
	li	a3,0
	mv	a0,a3
	addi	sp,s0,0
	lw	s0,0(sp)
	addi	sp,sp,4
	ret
.L4:
	.align	2
	.size	main, .-main
	.ident	"GCC: (15:9-2019-q4-0ubuntu1) 9.2.1 20191025 (release) [ARM/arm-9-branch revision 277599]"
