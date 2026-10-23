/**
 * Coverage for the custom exception. The type is also exercised by
 * LibraryServiceTest and LibraryBookLoanTriggerTest.
 */
@IsTest
private class NoAvailableCopiesExceptionTest {
    @IsTest
    static void carriesItsMessage() {
        try {
            throw new NoAvailableCopiesException('no available copies for testing');
        } catch (NoAvailableCopiesException e) {
            Assert.areEqual('no available copies for testing', e.getMessage());
        }
    }
}
