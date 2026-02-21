	.option nopic
	.attribute arch, "rv32i2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.file	"translated_from_arm.s"
	.text
	.section	.rodata
	.align	2
.LC0:
	.word	5
	.word	2
	.word	9
	.word	1
	.word	3
	.text
	.align	2
	.globl	main
	.type	main, %function
main:
	addi	sp,sp,-8
	sw	s0,0(sp)
	sw	ra,4(sp)
	addi	s0,sp,4
	addi	sp,sp,-40
	lui	a3,%hi(.LC0)
	addi	a3,a3,%lo(.LC0)
	addi	t0,s0,-44
	mv	ra,a3
	lw	a0,0(ra)
	lw	a1,4(ra)
	lw	a2,8(ra)
	lw	a3,12(ra)
	addi	ra,ra,16
	sw	a0,0(t0)
	sw	a1,4(t0)
	sw	a2,8(t0)
	sw	a3,12(t0)
	addi	t0,t0,16
	lw	a3,0(ra)
	sw	a3,0(t0)
	li	a3,5
	sw	a3,-20(s0)
	li	a3,0
	sw	a3,-8(s0)
	j	.L2
.L6:
	lw	a3,-8(s0)
	sw	a3,-12(s0)
	lw	a3,-8(s0)
	addi	a3,a3,1
	sw	a3,-16(s0)
	j	.L3
.L5:
	lw	a3,-16(s0)
	slli	a3,a3,2
	addi	a2,s0,-4
	add	a3,a2,a3
	lw	a2,-40(a3)
	lw	a3,-12(s0)
	slli	a3,a3,2
	addi	a1,s0,-4
	add	a3,a1,a3
	lw	a3,-40(a3)
	bge	a2,a3,.L4
	lw	a3,-16(s0)
	sw	a3,-12(s0)
.L4:
	lw	a3,-16(s0)
	addi	a3,a3,1
	sw	a3,-16(s0)
.L3:
	lw	a2,-16(s0)
	lw	a3,-20(s0)
	blt	a2,a3,.L5
	lw	a3,-8(s0)
	slli	a3,a3,2
	addi	a2,s0,-4
	add	a3,a2,a3
	lw	a3,-40(a3)
	sw	a3,-24(s0)
	lw	a3,-12(s0)
	slli	a3,a3,2
	addi	a2,s0,-4
	add	a3,a2,a3
	lw	a2,-40(a3)
	lw	a3,-8(s0)
	slli	a3,a3,2
	addi	a1,s0,-4
	add	a3,a1,a3
	sw	a2,-40(a3)
	lw	a3,-12(s0)
	slli	a3,a3,2
	addi	a2,s0,-4
	add	a3,a2,a3
	lw	a2,-24(s0)
	sw	a2,-40(a3)
	lw	a3,-8(s0)
	addi	a3,a3,1
	sw	a3,-8(s0)
.L2:
	lw	a3,-20(s0)
	addi	a3,a3,-1
	lw	a2,-8(s0)
	blt	a2,a3,.L6
	li	a3,0
	mv	a0,a3
	addi	sp,s0,-4
	lw	s0,0(sp)
	lw	ra,4(sp)
	addi	sp,sp,8
	ret
.L9:
	.align	2
	.size	main, .-main
	.ident	"GCC: (15:9-2019-q4-0ubuntu1) 9.2.1 20191025 (release) [ARM/arm-9-branch revision 277599]"
