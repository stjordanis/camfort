program range

implicit none

integer i, imax
parameter (imax = 3)

real a(0:imax), b(0:imax)

do i = 0, imax
   a(i+1) = b(i)
end do
  
end program
