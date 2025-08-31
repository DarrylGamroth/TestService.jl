"""
    try_claim(publication, length, max_attempts=10)

Try to claim a buffer from the stream with retries.
Returns the claim on success, nothing if no subscribers.
Throws ClaimBufferError if max attempts exceeded due to persistent back pressure.
"""
function try_claim(publication, length, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        claim, result = Aeron.try_claim(publication, length)
        if result > 0
            return claim
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            attempts -= 1
            if attempts > 0
                continue
            else
                throw(ClaimBufferError(
                    string(publication),
                    length,
                    max_attempts,
                    max_attempts
                ))
            end
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            # No subscribers connected - this is normal in some cases
            return nothing
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        else
            attempts -= 1
        end
    end
    throw(ClaimBufferError(
        string(publication),
        length,
        max_attempts - attempts,
        max_attempts
    ))
end

"""
    offer(publication, buffer, max_attempts=10)

Offer a buffer to the stream with retries.
Returns nothing on success or when no subscribers (both are normal cases).
Throws PublicationBackPressureError if max attempts exceeded due to persistent back pressure.
"""
function offer(publication, buffer, max_attempts=10)
    attempts = max_attempts
    while attempts > 0
        result = Aeron.offer(publication, buffer)
        if result > 0
            return nothing
        elseif result in (Aeron.PUBLICATION_BACK_PRESSURED, Aeron.PUBLICATION_ADMIN_ACTION)
            attempts -= 1
            if attempts > 0
                continue
            else
                throw(PublicationBackPressureError(
                    string(publication),
                    max_attempts,
                    max_attempts
                ))
            end
        elseif result == Aeron.PUBLICATION_NOT_CONNECTED
            # No subscribers connected - this is normal, just return
            return nothing
        elseif result == Aeron.PUBLICATION_ERROR
            Aeron.throwerror()
        else
            attempts -= 1
        end
    end
    throw(PublicationBackPressureError(
        string(publication),
        max_attempts - attempts,
        max_attempts
    ))
end
